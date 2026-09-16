defmodule Atlas.Coordination.Briefs.Adapter do
  alias Atlas.Coordination.Claims
  alias Atlas.Coordination.Detectors
  alias Atlas.Evidence

  def candidate_items(cadence, period) when cadence in ["daily", "weekly"] do
    _result = Detectors.refresh(period.end_at)
    claims = Claims.list_current()

    {:ok,
     %{
       summary: "#{length(claims)} current cross-domain claims connect signals across the company.",
       items: Enum.map(claims, &claim_item(&1, period)),
       generation_mode: "deterministic",
       generated_by_agent: "coordination_detector_v1"
     }}
  end

  defp claim_item(claim, period) do
    %{
      domain: "company",
      kind: "claim",
      title: claim_title(claim),
      detail: claim.statement,
      severity: claim_severity(claim),
      sensitivity: claim.sensitivity,
      materiality_score: claim.confidence,
      confidence: claim.confidence,
      suggested_action: suggested_action(claim.claim_kind),
      completion_condition: completion_condition(claim.claim_kind),
      fingerprint: "company:claim:#{claim.claim_kind}:#{claim.subject_account_id}",
      source_type: "cross_domain_claim",
      source_id: claim.id,
      source_path: "/sales/accounts/#{claim.subject_account_id}",
      due_at: DateTime.add(period.end_at, 7, :day),
      evidence: claim_evidence(claim)
    }
  end

  defp claim_evidence(claim) do
    "cross_domain_claim"
    |> Evidence.for_subject(claim.id)
    |> Enum.map(fn link ->
      %{
        record_type: link.record_type,
        record_id: link.record_id,
        source_class: link.source_class,
        sensitivity: link.sensitivity,
        observation: link.observation,
        occurred_at: link.occurred_at
      }
    end)
  end

  defp claim_title(%{claim_kind: "account_engagement_gap", subject_account: account}),
    do: "Engagement gap: #{account.name}"

  defp claim_title(%{claim_kind: "account_renewal_exposure", subject_account: account}),
    do: "Renewal exposure: #{account.name}"

  defp claim_title(%{claim_kind: "account_delivery_dependency", subject_account: account}),
    do: "Delivery dependency: #{account.name}"

  defp claim_severity(%{claim_kind: "account_renewal_exposure"}), do: "critical"
  defp claim_severity(_claim), do: "warning"

  defp suggested_action("account_engagement_gap"),
    do: "Choose a concrete re-engagement move or explicitly pause outreach."

  defp suggested_action("account_renewal_exposure"),
    do: "Assign a renewal recovery owner and review the account outcome."

  defp suggested_action("account_delivery_dependency"),
    do: "Confirm ownership and delivery timing with the account team."

  defp completion_condition("account_engagement_gap"), do: "A re-engagement decision is recorded."
  defp completion_condition("account_renewal_exposure"), do: "A renewal recovery plan has an owner."
  defp completion_condition("account_delivery_dependency"), do: "The dependency is delivered or explicitly rescheduled."
end
