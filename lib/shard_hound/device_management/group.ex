defmodule ShardHound.DeviceManagement.Group do
  use Ecto.Schema
  import Ecto.Changeset

  schema "groups" do
    field :name, :string
    field :description, :string
    field :filter, :map, default: %{}
    field :refreshed_at, :utc_datetime

    belongs_to :organization, ShardHound.DeviceManagement.Organization
    has_many :group_devices, ShardHound.DeviceManagement.GroupDevice

    many_to_many :devices, ShardHound.DeviceManagement.Device,
      join_through: ShardHound.DeviceManagement.GroupDevice

    timestamps(type: :utc_datetime)
  end

  def changeset(group, attrs) do
    group
    |> cast(attrs, [:name, :description, :filter, :refreshed_at])
    |> validate_required([:name, :filter])
    |> unique_constraint([:organization_id, :name])
  end
end
