defmodule ShardHound.PgDog.Admin do
  @moduledoc """
  Client for PgDog's admin database (`SHOW TASKS`, `MOVE KEYS`, ...).

  The admin database understands only its own command set: even the
  `pg_type` bootstrap query Postgres drivers run at connect is
  rejected, so Postgrex cannot hold a connection to it. Admin commands
  are plain text in and text rows out, which is exactly the wire
  protocol's simple query flow — this module speaks it directly over
  `:gen_tcp`. Commands are rare and operator-initiated: each call
  opens a connection, runs one command and closes.

  Connection settings live under `config :shard_hound, :pgdog_admin`.
  """

  @protocol_version 196_608
  @timeout 15_000

  @doc """
  Moves sharding keys to `target_shard` in one `MOVE KEYS` call and
  returns the task id. With `auto: true` (the default) the task cuts
  over on its own once replication catches up.
  """
  def move_keys(target_shard, keys, opts \\ []) when is_integer(target_shard) and keys != [] do
    auto = if Keyword.get(opts, :auto, true), do: " AUTO", else: ""
    keys = Enum.map_join(keys, ",", &to_string/1)

    case command("MOVE KEYS #{database()} #{target_shard} #{keys}#{auto}") do
      {:ok, [%{rows: [[task_id]]}]} -> {:ok, String.to_integer(task_id)}
      {:ok, other} -> {:error, "unexpected MOVE KEYS result: #{inspect(other)}"}
      {:error, message} -> {:error, message}
    end
  end

  @doc """
  Activates the next declared shard in one `ADD SHARD` call and
  returns the task id: schema sync, omnisharded data copy, WAL
  catch-up, then (with `auto: true`, the default) the coordinated
  cutover. The shard must have a `provisioning = true` entry in
  pgdog.toml and an empty database.
  """
  def add_shard(shard, opts \\ []) when is_integer(shard) do
    auto = if Keyword.get(opts, :auto, true), do: " AUTO", else: ""

    case command("ADD SHARD #{database()} #{shard}#{auto}") do
      {:ok, [%{rows: [[task_id]]}]} -> {:ok, String.to_integer(task_id)}
      {:ok, other} -> {:error, "unexpected ADD SHARD result: #{inspect(other)}"}
      {:error, message} -> {:error, message}
    end
  end

  @doc """
  The shard numbers PgDog is currently serving for the app database,
  from `SHOW POOLS`. Provisioning entries are excluded until their
  cutover, so this is the live topology.
  """
  def serving_shards do
    database = database()

    with {:ok, [%{columns: columns, rows: rows}]} <- command("SHOW POOLS") do
      shard = Enum.find_index(columns, &(&1 == "shard"))
      db = Enum.find_index(columns, &(&1 == "database"))

      shards =
        rows
        |> Enum.filter(&(Enum.at(&1, db) == database))
        |> Enum.map(&String.to_integer(Enum.at(&1, shard)))
        |> Enum.uniq()
        |> Enum.sort()

      {:ok, shards}
    end
  end

  @doc """
  Returns `SHOW TASKS` as a list of maps keyed by column name. Values
  are text; root tasks carry their id in `"id"`, subtasks an empty
  string.
  """
  def tasks do
    with {:ok, [%{columns: columns, rows: rows}]} <- command("SHOW TASKS") do
      {:ok, Enum.map(rows, fn row -> columns |> Enum.zip(row) |> Map.new() end)}
    end
  end

  @doc """
  Runs one admin command. Returns `{:ok, results}` where each result
  is `%{columns: [name], rows: [[text | nil]]}`.
  """
  def command(sql) do
    config =
      Application.get_env(:shard_hound, :pgdog_admin) ||
        raise "config :shard_hound, :pgdog_admin is not set; the admin client needs PgDog"

    with {:ok, socket, buffer} <- connect(config) do
      try do
        query = <<?Q, byte_size(sql) + 5::32, sql::binary, 0>>

        case :gen_tcp.send(socket, query) do
          :ok -> collect(socket, buffer, %{columns: [], rows: [], results: [], error: nil})
          {:error, reason} -> {:error, "admin socket error: #{inspect(reason)}"}
        end
      after
        :gen_tcp.close(socket)
      end
    end
  end

  ## Connection handshake

  defp connect(config) do
    host = String.to_charlist(config[:hostname])
    tcp_opts = [:binary, active: false, nodelay: true]

    startup =
      <<@protocol_version::32>> <>
        "user" <>
        <<0>> <>
        config[:username] <>
        <<0>> <>
        "database" <> <<0>> <> config[:database] <> <<0, 0>>

    with {:ok, socket} <- :gen_tcp.connect(host, config[:port], tcp_opts, @timeout),
         :ok <- :gen_tcp.send(socket, <<byte_size(startup) + 4::32, startup::binary>>),
         {:ok, buffer} <- authenticate(socket, config, <<>>) do
      {:ok, socket, buffer}
    else
      {:error, reason} when is_binary(reason) ->
        {:error, reason}

      {:error, reason} ->
        {:error, "could not connect to the PgDog admin database: #{inspect(reason)}"}
    end
  end

  defp authenticate(socket, config, buffer) do
    case recv_message(socket, buffer) do
      {:ok, ?R, <<0::32>>, buffer} ->
        await_ready(socket, buffer)

      {:ok, ?R, <<3::32>>, buffer} ->
        send_password(socket, config[:password])
        authenticate(socket, config, buffer)

      {:ok, ?R, <<5::32, salt::binary-size(4)>>, buffer} ->
        send_password(socket, md5_password(config, salt))
        authenticate(socket, config, buffer)

      {:ok, ?R, _unsupported, _buffer} ->
        {:error, "the admin client supports trust, cleartext and md5 auth only"}

      {:ok, ?E, payload, _buffer} ->
        {:error, error_message(payload)}

      {:ok, _other, _payload, buffer} ->
        authenticate(socket, config, buffer)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp await_ready(socket, buffer) do
    case recv_message(socket, buffer) do
      {:ok, ?Z, _payload, buffer} -> {:ok, buffer}
      {:ok, ?E, payload, _buffer} -> {:error, error_message(payload)}
      {:ok, _other, _payload, buffer} -> await_ready(socket, buffer)
      {:error, reason} -> {:error, reason}
    end
  end

  defp send_password(socket, password) do
    :gen_tcp.send(socket, <<?p, byte_size(password) + 5::32, password::binary, 0>>)
  end

  defp md5_password(config, salt) do
    inner = Base.encode16(:erlang.md5(config[:password] <> config[:username]), case: :lower)
    "md5" <> Base.encode16(:erlang.md5(inner <> salt), case: :lower)
  end

  ## Result collection

  defp collect(socket, buffer, acc) do
    case recv_message(socket, buffer) do
      {:ok, ?T, payload, buffer} ->
        collect(socket, buffer, %{acc | columns: parse_columns(payload), rows: []})

      {:ok, ?D, payload, buffer} ->
        collect(socket, buffer, %{acc | rows: [parse_row(payload) | acc.rows]})

      {:ok, ?C, _tag, buffer} ->
        result = %{columns: acc.columns, rows: Enum.reverse(acc.rows)}
        collect(socket, buffer, %{acc | columns: [], rows: [], results: [result | acc.results]})

      {:ok, ?E, payload, buffer} ->
        collect(socket, buffer, %{acc | error: error_message(payload)})

      {:ok, ?Z, _payload, _buffer} ->
        if acc.error, do: {:error, acc.error}, else: {:ok, Enum.reverse(acc.results)}

      {:ok, _other, _payload, buffer} ->
        collect(socket, buffer, acc)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # RowDescription: field count, then per field a NUL-terminated name
  # followed by 18 bytes of metadata we don't need for text results.
  defp parse_columns(<<_count::16, fields::binary>>), do: parse_column_fields(fields)

  defp parse_column_fields(<<>>), do: []

  defp parse_column_fields(fields) do
    [name, rest] = :binary.split(fields, <<0>>)
    <<_metadata::binary-size(18), rest::binary>> = rest
    [name | parse_column_fields(rest)]
  end

  # DataRow: column count, then per column a signed length (-1 is
  # NULL) and that many bytes of text.
  defp parse_row(<<_count::16, columns::binary>>), do: parse_row_columns(columns)

  defp parse_row_columns(<<>>), do: []

  defp parse_row_columns(<<-1::signed-32, rest::binary>>), do: [nil | parse_row_columns(rest)]

  defp parse_row_columns(<<size::signed-32, value::binary-size(size), rest::binary>>),
    do: [value | parse_row_columns(rest)]

  # ErrorResponse: NUL-terminated fields tagged by a type byte; ?M is
  # the human-readable message.
  defp error_message(payload) do
    payload
    |> :binary.split(<<0>>, [:global])
    |> Enum.find_value("unknown admin error", fn
      <<?M, message::binary>> -> message
      _other -> nil
    end)
  end

  ## Framing

  defp recv_message(socket, buffer) when byte_size(buffer) < 5 do
    recv_more(socket, buffer)
  end

  defp recv_message(socket, <<type, length::32, rest::binary>> = buffer) do
    payload_length = length - 4

    case rest do
      <<payload::binary-size(^payload_length), remaining::binary>> ->
        {:ok, type, payload, remaining}

      _incomplete ->
        recv_more(socket, buffer)
    end
  end

  defp recv_more(socket, buffer) do
    case :gen_tcp.recv(socket, 0, @timeout) do
      {:ok, data} -> recv_message(socket, buffer <> data)
      {:error, reason} -> {:error, "admin socket error: #{inspect(reason)}"}
    end
  end

  defp database do
    Application.fetch_env!(:shard_hound, ShardHound.Repo)[:database]
  end
end
