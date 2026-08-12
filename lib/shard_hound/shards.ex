defmodule ShardHound.Shards do
  @moduledoc """
  The application's placement policy: which shards accept new
  organizations. Backed by the omnisharded `shards` table, so every
  shard carries the same copy, writes broadcast through PgDog, and a
  shard provisioned by ADD SHARD receives it with the omni data sync.

  This is policy, not topology: `ShardHound.Topology` reports what
  PgDog is serving; this table says where new tenants may land.
  """

  import Ecto.Query

  require Logger

  alias ShardHound.DeviceManagement.Organization
  alias ShardHound.Repo
  alias ShardHound.Shards.Shard
  alias ShardHound.Topology

  def list do
    Repo.all(from shard in Shard, order_by: shard.shard_id)
  end

  @doc """
  The shards new organizations may be placed on. Falls back to the
  serving topology if every row is disabled, so generation never
  dead-ends.
  """
  def enabled_shard_ids do
    ids =
      Repo.all(
        from shard in Shard,
          where: shard.enabled_for_new_orgs,
          order_by: shard.shard_id,
          select: shard.shard_id
      )

    if ids == [] do
      Logger.warning("no shards are enabled for new organizations; using the full topology")
      Topology.shard_ids()
    else
      ids
    end
  end

  @doc """
  How many organizations are placed on each shard, as a map of shard
  id to count. One grouped read of the omnisharded organizations
  table: every shard holds the full copy, so any shard answers for
  the whole fleet.
  """
  def organization_counts do
    Organization
    |> group_by([o], o.shard_id)
    |> select([o], {o.shard_id, count(o.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc "Registers a newly activated shard, enabled for new organizations."
  def register(shard_id) when is_integer(shard_id) do
    Repo.insert!(%Shard{shard_id: shard_id},
      on_conflict: :nothing,
      conflict_target: :shard_id
    )

    :ok
  end

  def set_enabled(shard_id, enabled) when is_integer(shard_id) and is_boolean(enabled) do
    Repo.update_all(
      from(shard in Shard, where: shard.shard_id == ^shard_id),
      set: [enabled_for_new_orgs: enabled, updated_at: DateTime.utc_now(:second)]
    )

    :ok
  end
end
