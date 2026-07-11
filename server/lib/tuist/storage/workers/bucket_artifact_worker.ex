defmodule Tuist.Storage.Workers.BucketArtifactWorker do
  @moduledoc false

  alias Tuist.Storage.Workers.ArtifactRetentionWorker

  def options_from_args(args, nil), do: [continuation_token: Map.get(args, "continuation_token")]

  def options_from_args(args, retention_days) do
    [continuation_token: Map.get(args, "continuation_token"), retention_days: retention_days]
  end

  def continue(nil, _job, _retention_days, _self_hosted), do: :ok

  def continue(continuation_token, job, retention_days, self_hosted) do
    args =
      %{"continuation_token" => continuation_token}
      |> ArtifactRetentionWorker.put_retention_days(retention_days)
      |> ArtifactRetentionWorker.put_self_hosted(self_hosted)

    ArtifactRetentionWorker.reschedule_with_args(job, args)
  end
end
