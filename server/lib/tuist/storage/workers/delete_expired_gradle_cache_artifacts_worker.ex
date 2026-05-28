defmodule Tuist.Storage.Workers.DeleteExpiredGradleCacheArtifactsWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [keys: [:continuation_token], states: [:available, :scheduled, :executing, :retryable]]

  alias Tuist.Storage.CacheArtifactRetention

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    continuation_token = Map.get(args, "continuation_token")

    with {:ok, next_continuation_token} <-
           CacheArtifactRetention.delete_expired(:gradle, continuation_token: continuation_token) do
      maybe_enqueue_next_page(next_continuation_token)
    end
  end

  defp maybe_enqueue_next_page(nil), do: :ok

  defp maybe_enqueue_next_page(continuation_token) do
    %{"continuation_token" => continuation_token}
    |> __MODULE__.new()
    |> Oban.insert()
  end
end
