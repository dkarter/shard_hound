defmodule ShardHound.Shards.Shard do
  use Ecto.Schema

  @primary_key {:shard_id, :integer, autogenerate: false}
  schema "shards" do
    field :enabled_for_new_orgs, :boolean, default: true

    timestamps(type: :utc_datetime)
  end
end
