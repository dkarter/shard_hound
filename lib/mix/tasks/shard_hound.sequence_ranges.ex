defmodule Mix.Tasks.ShardHound.SequenceRanges do
  @shortdoc "Gives a shard's tenant id sequences a disjoint range"

  @moduledoc """
  Moves every tenant table's id sequence into a per-shard range so row
  ids are unique across the whole fleet.

  PgDog's MOVE KEYS copies rows verbatim: a moved row keeps its id on
  the target shard. With every shard's sequences starting at 1, two
  tenants on different shards routinely hold the same ids and a move
  aborts on a primary key collision. Shard `n` gets the range starting
  at `n * 1_000_000_000_000`; sequences already past their range start
  are left alone.

  Run once per shard, directly against it (not through PgDog):

      DATABASE_PORT=5433 mix shard_hound.sequence_ranges --shard 0
      DATABASE_PORT=5434 mix shard_hound.sequence_ranges --shard 1

  A shard provisioned by ADD SHARD copies the source's sequence state,
  so run it against a new shard too before assigning tenants to it:

      DATABASE_PORT=5435 mix shard_hound.sequence_ranges --shard 2
  """

  use Mix.Task

  @tenant_tables ~w(devices groups custom_packages device_software group_devices deployments commands)

  @impl Mix.Task
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: [shard: :integer])
    shard = Keyword.fetch!(opts, :shard)
    range_start = ShardHound.DemoData.sequence_range_start(shard)

    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = ShardHound.Repo.start_link(pool_size: 1)

    for table <- @tenant_tables do
      sequence = "#{table}_id_seq"

      %{rows: [[value]]} =
        ShardHound.Repo.query!(
          "SELECT setval('#{sequence}', GREATEST((SELECT last_value FROM #{sequence}), $1::bigint))",
          [range_start]
        )

      Mix.shell().info("#{sequence}: #{value}")
    end
  end
end
