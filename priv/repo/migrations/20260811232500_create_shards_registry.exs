defmodule ShardHound.Repo.Migrations.CreateShardsRegistry do
  use Ecto.Migration

  # Placement policy: new organizations round-robin over the enabled
  # rows. Omnisharded (broadcast), so every shard carries the same
  # copy and ADD SHARD's omni data sync hands it to a new shard for
  # free. shard_id is the primary key: a serial id would diverge
  # across broadcast inserts. It must be a bigint: PgDog's schema sync
  # upgrades integer primary keys to bigint on a new shard, and an
  # omnisharded table whose column types differ across shards breaks
  # prepared statements.
  def change do
    create table(:shards, primary_key: false) do
      add :shard_id, :bigint, primary_key: true
      add :enabled_for_new_orgs, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    execute(
      """
      INSERT INTO shards (shard_id, enabled_for_new_orgs, inserted_at, updated_at)
      VALUES (0, true, now(), now()), (1, true, now(), now())
      """,
      "DELETE FROM shards WHERE shard_id IN (0, 1)"
    )
  end
end
