defmodule Atlas.Coordination.Detectors do
  @moduledoc false

  import Ecto.Query

  alias Atlas.Accounts.Outcome
  alias Atlas.Accounts.Term
  alias Atlas.Coordination.Claims
  alias Atlas.Outreach.MessageAttempt
  alias Atlas.Repo

  @engagement_window_days 14
  @renewal_window_days 90

  def refresh(now \\ DateTime.utc_now()) do
    now = DateTime.truncate(now, :second)

    %{
      engagement_gaps: refresh_engagement_gaps(now),
      renewal_exposures: refresh_renewal_exposures(now)
    }
  end

  defp refresh_engagement_gaps(now) do
    before = DateTime.add(now, -@engagement_window_days, :day)

    attempts =
      MessageAttempt
      |> where([attempt], attempt.outcome == "pending" and attempt.sent_at <= ^before)
      |> order_by([attempt], asc: attempt.sent_at)
      |> preload(:account)
      |> Repo.all()
      |> Enum.uniq_by(& &1.account_id)

    outcomes =
      Outcome
      |> where([outcome], outcome.status == "active")
      |> order_by([outcome], asc: outcome.inserted_at, asc: outcome.id)
      |> Repo.all()
      |> Enum.group_by(& &1.account_id)

    Enum.flat_map(attempts, fn attempt ->
      outcomes
      |> Map.get(attempt.account_id, [])
      |> List.first()
      |> case do
        nil -> []
        outcome -> maybe_create_engagement_claim(attempt, outcome, now)
      end
    end)
  end

  defp refresh_renewal_exposures(now) do
    today = DateTime.to_date(now)
    ends_before = Date.add(today, @renewal_window_days)

    outcomes =
      Outcome
      |> where(
        [outcome],
        outcome.status == "active" and outcome.health in ["at_risk", "off_track"]
      )
      |> order_by([outcome], asc: outcome.inserted_at, asc: outcome.id)
      |> preload(:account)
      |> Repo.all()
      |> Enum.group_by(& &1.account_id)

    Term
    |> where(
      [term],
      not is_nil(term.end_date) and term.end_date >= ^today and term.end_date <= ^ends_before
    )
    |> order_by([term], asc: term.end_date)
    |> Repo.all()
    |> Enum.flat_map(fn term ->
      outcomes
      |> Map.get(term.account_id, [])
      |> List.first()
      |> case do
        nil -> []
        outcome -> maybe_create_renewal_claim(term, outcome, now)
      end
    end)
  end

  defp maybe_create_engagement_claim(attempt, outcome, now) do
    attrs = %{
      claim_kind: "account_engagement_gap",
      domains: ["accounts", "outreach"],
      statement:
        "#{attempt.account.name} has an active outcome, but the outreach sent on #{Date.to_iso8601(DateTime.to_date(attempt.sent_at))} has no recorded reply.",
      confidence: Decimal.new("0.90"),
      sensitivity: "internal",
      generated_by_agent: "coordination_detector_v1",
      valid_from: now
    }

    evidence = [
      %{
        record_type: "account_outcome",
        record_id: outcome.id,
        source_class: "decided",
        observation: "Active outcome: #{outcome.title}"
      },
      %{
        record_type: "outreach_message_attempt",
        record_id: attempt.id,
        source_class: "observed",
        observation: "Message sent at #{DateTime.to_iso8601(attempt.sent_at)} with no recorded reply"
      }
    ]

    case Claims.create(attempt.account, attrs, evidence, interface: "worker") do
      {:ok, claim} -> [claim]
      {:error, _reason} -> []
    end
  end

  defp maybe_create_renewal_claim(term, outcome, now) do
    account = outcome.account

    attrs = %{
      claim_kind: "account_renewal_exposure",
      domains: ["accounts", "finance"],
      statement:
        "#{account.name} renews on #{Date.to_iso8601(term.end_date)} while #{outcome.title} is #{String.replace(outcome.health, "_", " ")}.",
      confidence: Decimal.new("0.95"),
      sensitivity: "restricted",
      generated_by_agent: "coordination_detector_v1",
      valid_from: now
    }

    evidence = [
      %{
        record_type: "account_term",
        record_id: term.id,
        source_class: "observed",
        observation: "Current term ends on #{Date.to_iso8601(term.end_date)}"
      },
      %{
        record_type: "account_outcome",
        record_id: outcome.id,
        source_class: "decided",
        observation: "#{outcome.title} is #{String.replace(outcome.health, "_", " ")}"
      }
    ]

    case Claims.create(account, attrs, evidence, interface: "worker") do
      {:ok, claim} -> [claim]
      {:error, _reason} -> []
    end
  end
end
