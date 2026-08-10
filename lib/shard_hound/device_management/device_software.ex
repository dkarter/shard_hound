defmodule ShardHound.DeviceManagement.DeviceSoftware do
  use Ecto.Schema
  import Ecto.Changeset

  schema "device_software" do
    field :name, :string
    field :publisher, :string
    field :version, :string
    field :bundle_identifier, :string
    field :installed_at, :utc_datetime
    field :metadata, :map, default: %{}

    belongs_to :organization, ShardHound.DeviceManagement.Organization
    belongs_to :device, ShardHound.DeviceManagement.Device

    timestamps(type: :utc_datetime)
  end

  def changeset(software, attrs) do
    software
    |> cast(attrs, [:name, :publisher, :version, :bundle_identifier, :installed_at, :metadata])
    |> validate_required([:name, :version, :bundle_identifier])
    |> unique_constraint([:organization_id, :device_id, :bundle_identifier],
      name: :device_software_org_device_bundle_index
    )
  end
end
