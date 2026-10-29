defmodule Tuist.Storage.Workers.SweepExpiredRunArtifactsWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :storage_retention,
    max_attempts: 3,
    unique: [
      fields: [:queue, :worker],
      period: :infinity,
      states: :incomplete
    ]

  import Tuist.Storage.Workers.ArtifactRetentionWorker
  import Tuist.Storage.Workers.BucketArtifactWorker

  alias Tuist.Storage.RunArtifactRetention

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    with {:enabled, retention_days} <- effective_retention_days(args, :run_artifacts),
         {:ok, next_continuation_token} <-
           RunArtifactRetention.delete_expired(options_from_args(args, retention_days)) do
      continue(next_continuation_token, job, retention_days, Map.get(args, "self_hosted", false))
    else
      :disabled -> :ok
      error -> error
    end
  end
end
