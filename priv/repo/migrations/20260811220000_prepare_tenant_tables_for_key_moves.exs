defmodule ShardHound.Repo.Migrations.PrepareTenantTablesForKeyMoves do
  use Ecto.Migration

  # PgDog's MOVE KEYS replays tenant rows over logical replication.
  # DELETE and identity-only UPDATE events carry just the replica
  # identity columns, so the WAL filter can only route a change when
  # the identity covers organization_id. Each tenant table gets a
  # unique (organization_id, id) index (devices and groups already
  # have one) and uses it as its replica identity.
  @indexed ~w(custom_packages device_software group_devices deployments commands)a
  @tenant_tables ~w(devices groups)a ++ @indexed

  def change do
    for table <- @indexed do
      create unique_index(table, [:organization_id, :id])
    end

    for table <- @tenant_tables do
      execute(
        "ALTER TABLE #{table} REPLICA IDENTITY USING INDEX #{table}_organization_id_id_index",
        "ALTER TABLE #{table} REPLICA IDENTITY DEFAULT"
      )
    end
  end
end
