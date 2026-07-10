defmodule Tuist.Storage.Workers.BucketArtifactWorker do
  @moduledoc false

  alias Tuist.Storage.Workers.ArtifactRetentionWorker

  def options_from_args(args, retention_days) do
    maybe_put_retention_days([continuation_token: Map.get(args, "continuation_token")], retention_days)
  end

  def continue(nil, _job, _retention_days, _self_hosted), do: :ok

  def continue(continuation_token, job, retention_days, self_hosted) do
    args =
      %{"continuation_token" => continuation_token}
      |> maybe_put_retention_days(retention_days)
      |> maybe_put_self_hosted(self_hosted)

    ArtifactRetentionWorker.reschedule_with_args(job, args)
  end

  defp maybe_put_retention_days(args, nil), do: args

  defp maybe_put_retention_days(args, retention_days) when is_map(args) do
    Map.put(args, "retention_days", retention_days)
  end

  defp maybe_put_retention_days(opts, retention_days) when is_list(opts) do
    Keyword.put(opts, :retention_days, retention_days)
  end

  defp maybe_put_self_hosted(args, false), do: args
  defp maybe_put_self_hosted(args, true), do: Map.put(args, "self_hosted", true)
end
