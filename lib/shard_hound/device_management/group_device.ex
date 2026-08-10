defmodule ShardHound.DeviceManagement.GroupDevice do
  use Ecto.Schema
  import Ecto.Changeset

  schema "group_devices" do
    belongs_to :organization, ShardHound.DeviceManagement.Organization
    belongs_to :group, ShardHound.DeviceManagement.Group
    belongs_to :device, ShardHound.DeviceManagement.Device

    timestamps(type: :utc_datetime)
  end

  def changeset(group_device) do
    group_device
    |> cast(%{}, [])
    |> validate_required([:organization_id, :group_id, :device_id])
    |> unique_constraint([:organization_id, :group_id, :device_id])
  end
end
