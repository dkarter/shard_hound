defmodule ShardHound.DemoData do
  import Ecto.Query

  alias ShardHound.DemoData.GenerationParams
  alias ShardHound.DemoData.GenerateDatasetWorker
  alias ShardHound.DeviceManagement.Deployment
  alias ShardHound.DeviceManagement.Device
  alias ShardHound.DeviceManagement.DeviceSoftware
  alias ShardHound.DeviceManagement.Organization
  alias ShardHound.Repo
  alias ShardHound.Topology

  @terminal_states ~w(completed discarded cancelled)
  @active_states Oban.Job.states() |> Enum.map(&to_string/1) |> Kernel.--(@terminal_states)

  @omnisharded_tables ~w(organizations shard_hound_packages shards)
  @count_tables @omnisharded_tables ++
                  ~w(devices device_software groups group_devices custom_packages deployments commands)

  # Each shard's tenant id sequences live in a disjoint range so rows
  # keep their ids when MOVE KEYS relocates them.
  @sequence_range_size 1_000_000_000_000

  def sequence_range_start(shard), do: shard * @sequence_range_size

  @doc """
  Moves a shard's tenant id sequences into their disjoint range,
  routed through PgDog with `pgdog_shard` directives. Run against a
  shard that `ADD SHARD` just activated, before tenants land on it;
  `mix shard_hound.sequence_ranges` is the direct-connection
  equivalent for shards PgDog isn't serving yet.
  """
  def apply_sequence_ranges(shard) do
    base = sequence_range_start(shard)

    for table <- @count_tables -- @omnisharded_tables do
      sequence = "#{table}_id_seq"

      Repo.query!(
        "/* pgdog_shard: #{shard} */ SELECT setval('#{sequence}', GREATEST((SELECT last_value FROM #{sequence}), #{base}))"
      )
    end

    :ok
  end

  def change_generation(params \\ %GenerationParams{}, attrs \\ %{}) do
    GenerationParams.changeset(params, attrs)
  end

  def enqueue_generation(attrs) do
    changeset = change_generation(%GenerationParams{}, attrs)

    if changeset.valid? do
      generation_id = Ecto.UUID.generate()

      args =
        changeset
        |> Ecto.Changeset.apply_changes()
        |> Map.from_struct()
        |> Map.put(:generation_id, generation_id)

      case args |> GenerateDatasetWorker.new() |> Oban.insert() do
        {:ok, job} -> {:ok, generation_id, job}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, changeset}
    end
  end

  def generation_status(nil), do: empty_status()

  def generation_status(generation_id) do
    states =
      Oban.Job
      |> where(
        [job],
        fragment("? @> ?", job.args, type(^%{"generation_id" => generation_id}, :map))
      )
      |> group_by([job], job.state)
      |> select([job], {job.state, count(job.id)})
      |> oban_repo().all()
      |> Map.new()

    %{
      total: Enum.sum(Map.values(states)),
      active: sum_states(states, @active_states),
      completed: Map.get(states, "completed", 0),
      failed: sum_states(states, ~w(discarded cancelled)),
      states: states
    }
  end

  @doc """
  Re-asserts every tenant table's replica identity. The ADD SHARD
  schema sync carries the `(organization_id, id)` indexes but loses
  the `REPLICA IDENTITY USING INDEX` setting, which MOVE KEYS refuses
  on. DDL through PgDog broadcasts, so this reaches the new shard and
  no-ops on the rest.
  """
  def ensure_replica_identities do
    for table <- @count_tables -- @omnisharded_tables do
      Repo.query!(
        "ALTER TABLE #{table} REPLICA IDENTITY USING INDEX #{table}_organization_id_id_index"
      )
    end

    :ok
  end

  @doc """
  Lists every organization with its current placement. Organizations
  are omnisharded, so any shard answers with the full, identical set.
  """
  def organizations_with_shards do
    Organization
    |> order_by([o], asc: o.name, asc: o.id)
    |> select([o], %{id: o.id, name: o.name, shard_id: o.shard_id})
    |> Repo.all()
  end

  @doc """
  Audits tenant placement: every tenant row must live on the shard its
  organization's `shard_id` names. Each shard is asked, per tenant
  table, for rows whose local `organizations` copy (broadcast, so the
  placement column is the same everywhere) points at a different
  shard.

  Returns the total number of organizations, how many are clean, and
  one entry per organization with stray rows: which tables, on which
  shard, and how many rows. Rows copied by an in-flight MOVE KEYS task
  show up here until its cutover flips the placement.
  """
  def audit_placement do
    shards =
      if Application.fetch_env!(:shard_hound, :pgdog_enabled) do
        Topology.shard_ids()
      else
        []
      end

    problems =
      for shard <- shards,
          table <- @count_tables -- @omnisharded_tables,
          [id, name, expected_shard, count] <- wrong_shard_rows(table, shard),
          reduce: %{} do
        acc ->
          problem = %{table: table, shard: shard, count: count}

          Map.update(
            acc,
            id,
            %{id: id, name: name, expected_shard: expected_shard, rows: [problem]},
            &%{&1 | rows: [problem | &1.rows]}
          )
      end

    problems =
      problems
      |> Map.values()
      |> Enum.map(&%{&1 | rows: Enum.sort_by(&1.rows, fn row -> {row.table, row.shard} end)})
      |> Enum.sort_by(& &1.id)

    total = organization_count(shards)

    %{
      audited_at: DateTime.utc_now(:second),
      total: total,
      clean: total - length(problems),
      problems: problems
    }
  end

  defp wrong_shard_rows(table, shard) do
    %{rows: rows} =
      Repo.query!(
        "/* pgdog_shard: #{shard} */ " <>
          "SELECT o.id, o.name, o.shard_id, count(*) FROM #{table} t " <>
          "JOIN organizations o ON o.id = t.organization_id " <>
          "WHERE o.shard_id <> #{shard} GROUP BY o.id, o.name, o.shard_id"
      )

    rows
  end

  defp organization_count([]), do: Repo.aggregate(Organization, :count)
  defp organization_count([shard | _]), do: direct_count(Organization, shard)

  @doc """
  Deletes all generated demo data and clears the generation queue.

  `organizations` is omnisharded, so PgDog broadcasts the TRUNCATE to
  every shard, and CASCADE follows the foreign keys through every
  tenant table. Sequences are left alone: each shard keeps its
  disjoint id range. Running generation jobs are cancelled before the
  truncate so a mid-flight transaction can't repopulate tables.
  """
  def reset_demo_data do
    Oban.cancel_all_jobs(Oban.Job)
    Repo.query!("TRUNCATE organizations CASCADE")
    Repo.query!("TRUNCATE shard_hound_packages")
    oban_repo().delete_all(Oban.Job)
    :ok
  end

  def database_stats do
    if Application.fetch_env!(:shard_hound, :pgdog_enabled) do
      %{
        organizations: direct_count(Organization, 0),
        devices: sharded_count(Device),
        software: sharded_count(DeviceSoftware),
        deployments: sharded_count(Deployment)
      }
    else
      %{
        organizations: Repo.aggregate(Organization, :count),
        devices: Repo.aggregate(Device, :count),
        software: Repo.aggregate(DeviceSoftware, :count),
        deployments: Repo.aggregate(Deployment, :count)
      }
    end
  end

  @doc """
  Counts every table's rows on every shard, one direct count per
  shard via `pgdog_shard` directives. Omnisharded tables report the
  same figure on each shard because their rows are broadcast.

  Without PgDog there is a single unsharded database, reported as one
  `nil` shard.
  """
  def shard_table_counts do
    shards =
      if Application.fetch_env!(:shard_hound, :pgdog_enabled) do
        Topology.shard_ids()
      else
        [nil]
      end

    rows =
      for table <- @count_tables do
        %{
          table: table,
          omni: table in @omnisharded_tables,
          counts: Enum.map(shards, &table_count(table, &1))
        }
      end

    %{shards: shards, rows: rows}
  end

  defp sharded_count(schema) do
    Enum.reduce(Topology.shard_ids(), 0, fn shard, total ->
      total + direct_count(schema, shard)
    end)
  end

  defp direct_count(schema, shard) do
    table_count(schema.__schema__(:source), shard)
  end

  defp table_count(table, nil) do
    %{rows: [[count]]} = Repo.query!("SELECT count(*) FROM #{table}")
    count
  end

  defp table_count(table, shard) do
    %{rows: [[count]]} =
      Repo.query!("/* pgdog_shard: #{shard} */ SELECT count(*) FROM #{table}")

    count
  end

  def stable_id(value) do
    <<integer::unsigned-integer-size(64), _rest::binary>> = :crypto.hash(:sha256, value)
    rem(integer, 9_223_372_036_854_775_806) + 1
  end

  defp empty_status do
    %{total: 0, active: 0, completed: 0, failed: 0, states: %{}}
  end

  defp sum_states(states, names) do
    Enum.reduce(names, 0, &(&2 + Map.get(states, &1, 0)))
  end

  defp oban_repo do
    :shard_hound
    |> Application.fetch_env!(Oban)
    |> Keyword.fetch!(:repo)
  end
end
