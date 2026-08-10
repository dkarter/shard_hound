defmodule ShardHound.DeviceManagement.ShardHoundPackage do
  use Ecto.Schema
  import Ecto.Changeset

  schema "shard_hound_packages" do
    field :name, :string
    field :slug, :string
    field :platform, :string
    field :architecture, :string
    field :installer_type, :string
    field :latest_version, :string
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  def changeset(package, attrs) do
    package
    |> cast(attrs, [
      :name,
      :slug,
      :platform,
      :architecture,
      :installer_type,
      :latest_version,
      :metadata
    ])
    |> validate_required([
      :name,
      :slug,
      :platform,
      :architecture,
      :installer_type,
      :latest_version
    ])
    |> unique_constraint([:slug, :platform, :architecture])
  end
end
