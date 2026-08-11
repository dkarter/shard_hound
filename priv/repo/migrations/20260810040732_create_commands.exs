defmodule ShardHound.Repo.Migrations.CreateCommands do
  use Ecto.Migration

  def change do
    create table(:commands) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :device_id, references(:devices, on_delete: :delete_all), null: false
      add :command_script, :text

      timestamps()
    end
  end
end
