defmodule ShardHound.Topology do
  @moduledoc """
  The live shard topology, read from PgDog's serving pools so the app
  follows `ADD SHARD` activations without a restart: new organizations
  round-robin over the new shard, and the dashboard's per-shard
  queries grow a column, the moment a cutover lands.

  Falls back to the static `:shard_count` config when PgDog is
  disabled or unreachable.
  """

  require Logger

  alias ShardHound.PgDog
  alias ShardHound.Repo

  def shard_ids do
    with true <- Application.fetch_env!(:shard_hound, :pgdog_enabled),
         {:ok, shards} when shards != [] <- PgDog.Admin.serving_shards() do
      shards
    else
      false ->
        configured()

      other ->
        Logger.warning("falling back to configured shards: #{inspect(other)}")
        configured()
    end
  end

  def shard_count, do: length(shard_ids())

  @doc "The shard number the next `ADD SHARD` activates."
  def next_shard, do: shard_count()

  @doc """
  Copies the migration ledger onto a shard `ADD SHARD` just activated.
  The schema sync carries the DDL but not the `schema_migrations`
  rows, so without this the shard reports every migration as pending —
  Phoenix's dev repo-status check 503s when a read lands there, and
  `mix ecto.migrate` would re-run everything.
  """
  def adopt_schema_migrations(_shard) do
    %{rows: rows} = Repo.query!("/* pgdog_shard: 0 */ SELECT version FROM schema_migrations")

    # PgDog broadcasts writes to unlisted unsharded tables (and refuses
    # to route them to one shard), so the idempotent insert reaches the
    # new shard and no-ops everywhere the ledger already exists.
    for [version] <- rows do
      Repo.query!(
        "INSERT INTO schema_migrations (version, inserted_at) " <>
          "VALUES (#{version}, now()) ON CONFLICT DO NOTHING"
      )
    end

    :ok
  end

  defp configured do
    Enum.to_list(0..(Application.fetch_env!(:shard_hound, :shard_count) - 1))
  end
end
