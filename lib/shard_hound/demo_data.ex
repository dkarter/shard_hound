defmodule ShardHound.DemoData do
  import Ecto.Query

  alias ShardHound.DemoData.GenerationParams
  alias ShardHound.DemoData.GenerateDatasetWorker
  alias ShardHound.Repo

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
      |> where([job], fragment("?->>'generation_id' = ?", job.args, ^generation_id))
      |> group_by([job], job.state)
      |> select([job], {job.state, count(job.id)})
      |> Repo.all()
      |> Map.new()

    %{
      total: Enum.sum(Map.values(states)),
      active: sum_states(states, ~w(available scheduled executing retryable)),
      completed: Map.get(states, "completed", 0),
      failed: sum_states(states, ~w(discarded cancelled)),
      states: states
    }
  end

  defp empty_status do
    %{total: 0, active: 0, completed: 0, failed: 0, states: %{}}
  end

  defp sum_states(states, names) do
    Enum.reduce(names, 0, &(&2 + Map.get(states, &1, 0)))
  end
end
