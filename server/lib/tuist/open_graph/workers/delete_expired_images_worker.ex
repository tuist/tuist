defmodule Tuist.OpenGraph.Workers.DeleteExpiredImagesWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :storage_retention,
    max_attempts: 3,
    unique: [fields: [:queue, :worker], period: :infinity, states: :incomplete]

  alias Tuist.OpenGraphImageRetention
  alias Tuist.Storage.Workers.ArtifactRetentionWorker

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    case OpenGraphImageRetention.delete_expired(continuation_token: Map.get(args, "continuation_token")) do
      {:ok, nil} ->
        :ok

      {:ok, continuation_token} ->
        ArtifactRetentionWorker.reschedule_with_args(job, %{"continuation_token" => continuation_token})

      {:error, _reason} = error ->
        error
    end
  end
end
