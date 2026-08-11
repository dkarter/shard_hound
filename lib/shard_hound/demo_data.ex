defmodule ShardHound.DemoData do
  import Ecto.Query

  alias ShardHound.DemoData.GenerationParams
  alias ShardHound.DemoData.GenerateDatasetWorker
  alias ShardHound.DeviceManagement.Deployment
  alias ShardHound.DeviceManagement.Device
  alias ShardHound.DeviceManagement.DeviceSoftware
  alias ShardHound.DeviceManagement.Organization
  alias ShardHound.Repo

  @terminal_states ~w(completed discarded cancelled)
  @active_states Oban.Job.states() |> Enum.map(&to_string/1) |> Kernel.--(@terminal_states)

  def change_generation(params \\ %GenerationParams{}, attrs \\ %{}) do
    GenerationParams.changeset(params, attrs)
  end

  def enqueue_generation(attrs) do
    changeset = change_generation(%GenerationParams{}, attrs)

    if changeset.valid? do
      generation_id = Ecto.UUID.generate()

      args =
        changeset
        |> Ecto.Changeset.apply_changes()
        |> Map.from_struct()
        |> Map.put(:generation_id, generation_id)

      case args |> GenerateDatasetWorker.new() |> Oban.insert() do
        {:ok, job} -> {:ok, generation_id, job}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, changeset}
    end
  end

  def generation_status(nil), do: empty_status()

  def generation_status(generation_id) do
    states =
      Oban.Job
      |> where(
        [job],
        fragment("? @> ?", job.args, type(^%{"generation_id" => generation_id}, :map))
      )
      |> group_by([job], job.state)
      |> select([job], {job.state, count(job.id)})
      |> oban_repo().all()
      |> Map.new()

    %{
      total: Enum.sum(Map.values(states)),
      active: sum_states(states, @active_states),
      completed: Map.get(states, "completed", 0),
      failed: sum_states(states, ~w(discarded cancelled)),
      states: states
    }
  end

  def database_stats do
    if Application.fetch_env!(:shard_hound, :pgdog_enabled) do
      %{
        organizations: direct_count(Organization, 0),
        devices: sharded_count(Device),
        software: sharded_count(DeviceSoftware),
        deployments: sharded_count(Deployment)
      }
    else
      %{
        organizations: Repo.aggregate(Organization, :count),
        devices: Repo.aggregate(Device, :count),
        software: Repo.aggregate(DeviceSoftware, :count),
        deployments: Repo.aggregate(Deployment, :count)
      }
    end
  end

  defp sharded_count(schema) do
    shard_count = Application.fetch_env!(:shard_hound, :shard_count)

    Enum.reduce(0..(shard_count - 1), 0, fn shard, total ->
      total + direct_count(schema, shard)
    end)
  end

  defp direct_count(schema, shard) do
    table = schema.__schema__(:source)

    %{rows: [[count]]} =
      Repo.query!("/* pgdog_shard: #{shard} */ SELECT count(*) FROM #{table}")

    count
  end

  def stable_id(value) do
    <<integer::unsigned-integer-size(64), _rest::binary>> = :crypto.hash(:sha256, value)
    rem(integer, 9_223_372_036_854_775_806) + 1
  end

  defp empty_status do
    %{total: 0, active: 0, completed: 0, failed: 0, states: %{}}
  end

  defp sum_states(states, names) do
    Enum.reduce(names, 0, &(&2 + Map.get(states, &1, 0)))
  end

  defp oban_repo do
    :shard_hound
    |> Application.fetch_env!(Oban)
    |> Keyword.fetch!(:repo)
  end
end
