defmodule ShardHound.DeviceManagement.Deployment do
  use Ecto.Schema
  import Ecto.Changeset

  @package_types ~w(shard_hound custom)
  @statuses ~w(pending scheduled running completed failed)

  schema "deployments" do
    field :package_id, :integer
    field :package_type, :string
    field :name, :string
    field :target_version, :string
    field :status, :string, default: "pending"
    field :scheduled_at, :utc_datetime
    field :metadata, :map, default: %{}

    belongs_to :organization, ShardHound.DeviceManagement.Organization
    belongs_to :group, ShardHound.DeviceManagement.Group

    timestamps(type: :utc_datetime)
  end

  def changeset(deployment, attrs) do
    deployment
    |> cast(attrs, [
      :package_id,
      :package_type,
      :name,
      :target_version,
      :status,
      :scheduled_at,
      :metadata
    ])
    |> validate_required([:package_id, :package_type, :name, :target_version, :status])
    |> validate_inclusion(:package_type, @package_types)
    |> validate_inclusion(:status, @statuses)
  end
end
