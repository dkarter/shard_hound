defmodule ShardHound.DeviceManagement.Device do
  use Ecto.Schema
  import Ecto.Changeset

  schema "devices" do
    field :serial_number, :string
    field :hostname, :string
    field :platform, :string
    field :architecture, :string
    field :os_version, :string
    field :last_seen_at, :utc_datetime
    field :metadata, :map, default: %{}

    belongs_to :organization, ShardHound.DeviceManagement.Organization
    has_many :software, ShardHound.DeviceManagement.DeviceSoftware
    has_many :group_devices, ShardHound.DeviceManagement.GroupDevice

    many_to_many :groups, ShardHound.DeviceManagement.Group,
      join_through: ShardHound.DeviceManagement.GroupDevice

    timestamps(type: :utc_datetime)
  end

  def changeset(device, attrs) do
    device
    |> cast(attrs, [
      :serial_number,
      :hostname,
      :platform,
      :architecture,
      :os_version,
      :last_seen_at,
      :metadata
    ])
    |> validate_required([:serial_number, :hostname, :platform, :architecture, :os_version])
    |> unique_constraint([:organization_id, :serial_number])
  end
end
