defmodule Tuist.Storage.Workers.DeleteExpiredCasCacheArtifactsWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :storage_retention,
    max_attempts: 3,
    unique: [
      fields: [:queue, :worker],
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable]
    ]

  import Tuist.Storage.Workers.ArtifactRetentionWorker
  import Tuist.Storage.Workers.BucketArtifactWorker

  alias Tuist.Storage.CacheArtifactRetention

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    with {:enabled, retention_days} <- effective_retention_days(args, :cache_artifacts),
         {:ok, next_continuation_token} <-
           CacheArtifactRetention.delete_expired(:cas, options_from_args(args, retention_days)) do
      continue(next_continuation_token, job, retention_days, Map.get(args, "self_hosted", false))
    else
      :disabled -> :ok
      error -> error
    end
  end
end
