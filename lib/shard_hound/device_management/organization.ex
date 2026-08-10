defmodule ShardHound.DeviceManagement.Organization do
  use Ecto.Schema
  import Ecto.Changeset

  schema "organizations" do
    field :name, :string
    field :slug, :string

    has_many :devices, ShardHound.DeviceManagement.Device
    has_many :groups, ShardHound.DeviceManagement.Group
    has_many :custom_packages, ShardHound.DeviceManagement.CustomPackage
    has_many :deployments, ShardHound.DeviceManagement.Deployment

    timestamps(type: :utc_datetime)
  end

  def changeset(organization, attrs) do
    organization
    |> cast(attrs, [:name, :slug])
    |> validate_required([:name, :slug])
    |> unique_constraint(:slug)
  end
end
