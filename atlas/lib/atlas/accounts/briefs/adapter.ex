defmodule Atlas.Accounts.Briefs.Adapter do
  import Ecto.Query

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Outcome
  alias Atlas.Accounts.OutcomeProposal
  alias Atlas.Repo

  @stale_review_days 30

  def candidate_items(cadence, period) when cadence in ["daily", "weekly"] do
    proposals = pending_proposals()
    outcomes = outcomes_needing_attention(period.end_at)

    {:ok,
     %{
       summary: summary(proposals, outcomes),
       items: proposal_items(proposals, period) ++ outcome_items(outcomes, period),
       generation_mode: "deterministic",
       generated_by_agent: nil
     }}
  end

  defp pending_proposals do
    OutcomeProposal
    |> where([proposal], proposal.status == "pending")
    |> order_by([proposal], desc: proposal.confidence, asc: proposal.inserted_at)
    |> preload([:account, :outcome])
    |> Repo.all()
  end

  defp outcomes_needing_attention(now) do
    stale_before = DateTime.add(now, -@stale_review_days, :day)

    Outcome
    |> where(
      [outcome],
      outcome.status == "active" and
        (outcome.health in ["at_risk", "off_track"] or is_nil(outcome.reviewed_at) or
           outcome.reviewed_at < ^stale_before)
    )
    |> order_by([outcome], asc: outcome.health, asc_nulls_first: outcome.reviewed_at)
    |> preload(:account)
    |> Repo.all()
  end

  defp proposal_items(proposals, period) do
    Enum.map(proposals, fn proposal ->
      %{
        domain: "accounts",
        kind: "proposal",
        title: proposal_title(proposal),
        detail: proposal.rationale,
        severity: proposal_severity(proposal),
        sensitivity: "internal",
        materiality_score: proposal.confidence || Decimal.new("0.70"),
        confidence: proposal.confidence,
        suggested_action: "Review the proposal in the account workspace.",
        completion_condition: "The proposal is approved or rejected with a reason.",
        fingerprint: "accounts:outcome_proposal:#{proposal.account_id}:#{proposal.proposal_key}",
        source_type: "account_outcome_proposal",
        source_id: proposal.id,
        source_path: "/sales/accounts/#{proposal.account_id}",
        due_at: DateTime.add(period.end_at, 7, :day),
        evidence: proposal_evidence(proposal)
      }
    end)
  end

  defp outcome_items(outcomes, period) do
    Enum.map(outcomes, fn outcome ->
      stale? =
        is_nil(outcome.reviewed_at) or DateTime.diff(period.end_at, outcome.reviewed_at, :day) >= @stale_review_days

      kind = if stale?, do: "expectation_missed", else: "risk"

      %{
        domain: "accounts",
        kind: kind,
        title: "#{outcome.account.name}: #{outcome.title}",
        detail: outcome_detail(outcome, stale?),
        severity: outcome_severity(outcome),
        sensitivity: "internal",
        materiality_score: outcome_score(outcome),
        suggested_action: "Review the outcome and record the next customer move.",
        completion_condition: "The outcome has a current review and an explicit next step.",
        fingerprint: "accounts:outcome:#{outcome.id}:#{kind}",
        source_type: "account_outcome",
        source_id: outcome.id,
        source_path: "/sales/accounts/#{outcome.account_id}",
        due_at: DateTime.add(period.end_at, 7, :day),
        evidence: [
          %{
            record_type: "account_outcome",
            record_id: outcome.id,
            source_class: "decided",
            observation: "Outcome health is #{String.replace(outcome.health, "_", " ")}"
          }
        ]
      }
    end)
  end

  defp proposal_evidence(%OutcomeProposal{evidence: %{"items" => items}}) when is_list(items) do
    Enum.flat_map(items, fn item ->
      case item["event_id"] do
        id when is_binary(id) ->
          [
            %{
              record_type: "account_event",
              record_id: id,
              source_class: "observed",
              observation: item["observation"] || "Account event"
            }
          ]

        _id ->
          []
      end
    end)
  end

  defp proposal_evidence(_proposal), do: []

  defp proposal_title(%OutcomeProposal{proposal_type: "new_outcome", account: %Account{} = account} = proposal),
    do: "#{account.name}: consider #{proposal.title}"

  defp proposal_title(%OutcomeProposal{account: %Account{} = account, outcome: %Outcome{} = outcome}),
    do: "#{account.name}: review #{outcome.title}"

  defp proposal_title(proposal), do: proposal.title || "Review account outcome proposal"

  defp proposal_severity(%OutcomeProposal{health: "off_track"}), do: "critical"
  defp proposal_severity(%OutcomeProposal{health: "at_risk"}), do: "warning"
  defp proposal_severity(_proposal), do: "info"

  defp outcome_severity(%Outcome{health: "off_track"}), do: "critical"
  defp outcome_severity(%Outcome{health: "at_risk"}), do: "warning"
  defp outcome_severity(_outcome), do: "info"

  defp outcome_score(%Outcome{health: "off_track"}), do: Decimal.new("0.95")
  defp outcome_score(%Outcome{health: "at_risk"}), do: Decimal.new("0.80")
  defp outcome_score(_outcome), do: Decimal.new("0.60")

  defp outcome_detail(outcome, true) do
    "This active outcome has no review in the last #{@stale_review_days} days. Current health is #{String.replace(outcome.health, "_", " ")}."
  end

  defp outcome_detail(outcome, false) do
    "The active outcome is #{String.replace(outcome.health, "_", " ")} and needs a concrete recovery move."
  end

  defp summary(proposals, outcomes) do
    "#{length(proposals)} outcome proposals await review and #{length(outcomes)} active outcomes need attention."
  end
end
