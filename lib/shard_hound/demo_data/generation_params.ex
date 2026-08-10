defmodule ShardHound.DemoData.GenerationParams do
  use Ecto.Schema
  import Ecto.Changeset

  @count_fields [
    %{name: :organizations, label: "Organizations", min: 1, max: 500},
    %{name: :devices_per_organization, label: "Devices / organization", min: 1, max: 5_000},
    %{name: :software_per_device, label: "Software / device", min: 1, max: 10},
    %{name: :groups_per_organization, label: "Groups / organization", min: 1, max: 10},
    %{
      name: :custom_packages_per_organization,
      label: "Custom packages / organization",
      min: 0,
      max: 50
    },
    %{
      name: :deployments_per_organization,
      label: "Deployments / organization",
      min: 0,
      max: 100
    },
    %{name: :managed_packages, label: "Shared managed packages", min: 1, max: 10}
  ]

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

  def count_fields, do: @count_fields

  def changeset(params, attrs \\ %{}) do
    fields = Enum.map(@count_fields, & &1.name)

    params
    |> cast(attrs, fields)
    |> validate_required(fields)
    |> validate_number(:organizations, greater_than: 0, less_than_or_equal_to: 500)
    |> validate_number(:devices_per_organization,
      greater_than: 0,
      less_than_or_equal_to: 5_000
    )
    |> validate_number(:software_per_device, greater_than: 0, less_than_or_equal_to: 10)
    |> validate_number(:groups_per_organization, greater_than: 0, less_than_or_equal_to: 10)
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
