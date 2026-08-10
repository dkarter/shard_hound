defmodule ShardHound.DemoData.GenerationParams do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :organizations, :integer, default: 5
    field :devices_per_organization, :integer, default: 100
    field :software_per_device, :integer, default: 6
    field :groups_per_organization, :integer, default: 4
    field :custom_packages_per_organization, :integer, default: 3
    field :deployments_per_organization, :integer, default: 5
    field :managed_packages, :integer, default: 8
  end

  def changeset(params, attrs \\ %{}) do
    params
    |> cast(attrs, [
      :organizations,
      :devices_per_organization,
      :software_per_device,
      :groups_per_organization,
      :custom_packages_per_organization,
      :deployments_per_organization,
      :managed_packages
    ])
    |> validate_required([
      :organizations,
      :devices_per_organization,
      :software_per_device,
      :groups_per_organization,
      :custom_packages_per_organization,
      :deployments_per_organization,
      :managed_packages
    ])
    |> validate_number(:organizations, greater_than: 0, less_than_or_equal_to: 500)
    |> validate_number(:devices_per_organization,
      greater_than: 0,
      less_than_or_equal_to: 5_000
    )
    |> validate_number(:software_per_device, greater_than: 0, less_than_or_equal_to: 25)
    |> validate_number(:groups_per_organization, greater_than: 0, less_than_or_equal_to: 50)
    |> validate_number(:custom_packages_per_organization,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 50
    )
    |> validate_number(:deployments_per_organization,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 100
    )
    |> validate_number(:managed_packages, greater_than: 0, less_than_or_equal_to: 10)
    |> validate_software_count()
  end

  defp validate_software_count(changeset) do
    software_count = get_field(changeset, :software_per_device)
    package_count = get_field(changeset, :managed_packages)

    if software_count && package_count && software_count > package_count do
      add_error(changeset, :software_per_device, "cannot exceed managed packages")
    else
      changeset
    end
  end
end
