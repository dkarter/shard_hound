defmodule ShardHound.Repo.Migrations.AddShardIdToOrganizations do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :shard_id, :integer, null: false, default: 0
    end

    create index(:organizations, [:shard_id])
  end
end
