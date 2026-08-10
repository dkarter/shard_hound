defmodule ShardHound.DeviceManagement.CustomPackage do
  use Ecto.Schema
  import Ecto.Changeset

  schema "custom_packages" do
    field :name, :string
    field :slug, :string
    field :platform, :string
    field :architecture, :string
    field :installer_type, :string
    field :latest_version, :string
    field :metadata, :map, default: %{}

    belongs_to :organization, ShardHound.DeviceManagement.Organization

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
    |> unique_constraint([:organization_id, :slug, :platform, :architecture],
      name: :custom_packages_org_slug_platform_arch_index
    )
  end
end
