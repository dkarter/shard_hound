defmodule ShardHound.Repo.Migrations.CreateDeviceManagementTables do
  use Ecto.Migration

  def change do
    create table(:organizations) do
      add :name, :string, null: false
      add :slug, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:organizations, [:slug])

    create table(:shard_hound_packages) do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :platform, :string, null: false
      add :architecture, :string, null: false
      add :installer_type, :string, null: false
      add :latest_version, :string, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:shard_hound_packages, [:slug, :platform, :architecture])

    create table(:devices) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :serial_number, :string, null: false
      add :hostname, :string, null: false
      add :platform, :string, null: false
      add :architecture, :string, null: false
      add :os_version, :string, null: false
      add :last_seen_at, :utc_datetime
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:devices, [:organization_id, :id])
    create unique_index(:devices, [:organization_id, :serial_number])
    create index(:devices, [:organization_id, :platform])

    create table(:groups) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :description, :text
      add :filter, :map, null: false, default: %{}
      add :refreshed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:groups, [:organization_id, :id])
    create unique_index(:groups, [:organization_id, :name])

    create table(:custom_packages) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :slug, :string, null: false
      add :platform, :string, null: false
      add :architecture, :string, null: false
      add :installer_type, :string, null: false
      add :latest_version, :string, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(
             :custom_packages,
             [
               :organization_id,
               :slug,
               :platform,
               :architecture
             ],
             name: :custom_packages_org_slug_platform_arch_index
           )

    create table(:device_software) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :device_id, :bigint, null: false
      add :name, :string, null: false
      add :publisher, :string
      add :version, :string, null: false
      add :bundle_identifier, :string, null: false
      add :installed_at, :utc_datetime
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:device_software, [:organization_id, :device_id])
    create index(:device_software, [:organization_id, :name, :version])

    create unique_index(
             :device_software,
             [
               :organization_id,
               :device_id,
               :bundle_identifier
             ],
             name: :device_software_org_device_bundle_index
           )

    create table(:group_devices) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :group_id, :bigint, null: false
      add :device_id, :bigint, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:group_devices, [:organization_id, :device_id])
    create unique_index(:group_devices, [:organization_id, :group_id, :device_id])

    create table(:deployments) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :group_id, :bigint
      add :package_id, :bigint, null: false
      add :package_type, :string, null: false
      add :name, :string, null: false
      add :target_version, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :scheduled_at, :utc_datetime
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:deployments, [:organization_id, :group_id])
    create index(:deployments, [:organization_id, :package_type, :package_id])

    create constraint(:deployments, :deployments_package_type_check,
             check: "package_type IN ('shard_hound', 'custom')"
           )

    create constraint(:deployments, :deployments_status_check,
             check: "status IN ('pending', 'scheduled', 'running', 'completed', 'failed')"
           )

    execute """
            ALTER TABLE device_software
            ADD CONSTRAINT device_software_organization_device_fkey
            FOREIGN KEY (organization_id, device_id)
            REFERENCES devices (organization_id, id)
            ON DELETE CASCADE
            """,
            "ALTER TABLE device_software DROP CONSTRAINT device_software_organization_device_fkey"

    execute """
            ALTER TABLE group_devices
            ADD CONSTRAINT group_devices_organization_group_fkey
            FOREIGN KEY (organization_id, group_id)
            REFERENCES groups (organization_id, id)
            ON DELETE CASCADE
            """,
            "ALTER TABLE group_devices DROP CONSTRAINT group_devices_organization_group_fkey"

    execute """
            ALTER TABLE group_devices
            ADD CONSTRAINT group_devices_organization_device_fkey
            FOREIGN KEY (organization_id, device_id)
            REFERENCES devices (organization_id, id)
            ON DELETE CASCADE
            """,
            "ALTER TABLE group_devices DROP CONSTRAINT group_devices_organization_device_fkey"

    execute """
            ALTER TABLE deployments
            ADD CONSTRAINT deployments_organization_group_fkey
            FOREIGN KEY (organization_id, group_id)
            REFERENCES groups (organization_id, id)
            ON DELETE SET NULL (group_id)
            """,
            "ALTER TABLE deployments DROP CONSTRAINT deployments_organization_group_fkey"
  end
end
