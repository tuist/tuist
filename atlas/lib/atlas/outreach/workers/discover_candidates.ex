defmodule Atlas.Outreach.Workers.DiscoverCandidates do
  @moduledoc """
  Discovers outreach candidates and announces each new candidate in Slack.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [period: :timer.hours(23)]

  alias Atlas.Audit
  alias Atlas.Outreach
  alias Atlas.Outreach.CandidateNotifier

  @impl true
  def perform(%Oban.Job{}) do
    Audit.with_context(%{interface: "worker"}, fn ->
      with :ok <- notify_pending_candidates(),
           {:ok, result} <- Outreach.search_apollo(),
           :ok <- notify_pending_candidates() do
        audit_discovery(result)
        :ok
      else
        {:error, {_segment, :apollo_api_key_not_configured}} ->
          {:cancel, :apollo_api_key_not_configured}

        {:error, reason} ->
          {:error, reason}
      end
    end)
  end

  defp notify_pending_candidates do
    Outreach.list_candidates_pending_notification()
    |> Enum.reduce_while(:ok, fn candidate, :ok ->
      with {:ok, notification} <- CandidateNotifier.notify(candidate),
           {:ok, _candidate} <- Outreach.mark_candidate_notified(candidate, notification) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp audit_discovery(result) do
    Audit.record("outreach.discovery_completed", %{
      target_type: "outreach_search",
      target_id: "apollo-outreach-discovery",
      target_label: "Daily outreach discovery",
      metadata: %{
        "created" => result.created,
        "updated" => result.updated,
        "excluded" => result.excluded,
        "returned" => result.returned,
        "total_matches" => result.total_matches,
        "path" => "/gtm/outreach"
      }
    })
  end
end
