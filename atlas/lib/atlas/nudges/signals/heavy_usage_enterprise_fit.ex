defmodule Atlas.Nudges.Signals.HeavyUsageEnterpriseFit do
  @moduledoc """
  Fires when a paying customer has crossed `@min_thresholds` distinct
  Air (`runner_minutes`) notification thresholds in the current billing
  period, and their plan tier is not already `enterprise`. The pitch is
  a conversation about moving them to enterprise pricing.

  Reads the pre-aggregated status landed by
  `Atlas.Nudges.Workers.RefreshAirStatusForAccount`.
  """

  import Ecto.Query

  alias Atlas.Accounts.Account
  alias Atlas.Nudges
  alias Atlas.Nudges.Analytics
  alias Atlas.Nudges.Analytics.AirStatus
  alias Atlas.Nudges.Proposal
  alias Atlas.Repo

  @signal_name "heavy_usage_enterprise_fit"
  @min_thresholds 3
  @staleness_hours 48

  def name, do: @signal_name

  def candidate_account_ids do
    Account
    |> where([a], not is_nil(a.plan_tier))
    |> where([a], a.plan_tier not in ["free", "enterprise"])
    |> where([a], is_nil(a.not_an_account_at))
    |> select([a], a.id)
    |> Repo.all()
  end

  def evaluate(%Account{} = account) do
    with %AirStatus{refresh_status: "ok"} = status <- Analytics.air_status(account),
         false <- stale?(status),
         true <- status.distinct_thresholds_delivered >= @min_thresholds do
      dispatch(account, status)
    else
      false -> maybe_close_episode(account)
      _no_data -> :skip
    end
  end

  defp stale?(%AirStatus{computed_at: computed_at}) when is_struct(computed_at, DateTime) do
    DateTime.diff(DateTime.utc_now(), computed_at, :hour) > @staleness_hours
  end

  defp stale?(_status), do: true

  defp dispatch(%Account{} = account, %AirStatus{} = status) do
    evidence = %{
      "distinct_thresholds_delivered" => status.distinct_thresholds_delivered,
      "period_start" => Date.to_iso8601(status.period_start),
      "metric" => status.metric,
      "threshold" => @min_thresholds,
      "plan_tier" => account.plan_tier
    }

    case Nudges.open_or_touch_episode(account, @signal_name, evidence) do
      {:existing, _episode} -> :skip
      {:opened, episode} -> {:ok, build_proposal(account, episode, status, evidence)}
      {:error, _reason} -> :skip
    end
  end

  defp build_proposal(%Account{} = account, episode, %AirStatus{} = status, evidence) do
    contact = Nudges.select_contact_for(account)
    account_label = account_label(account)

    %Proposal{
      dedup_key: "#{@signal_name}:#{episode.id}",
      title:
        "#{account_label}: enterprise conversation (#{status.distinct_thresholds_delivered} usage crossings this period)",
      rationale:
        "#{account_label} has crossed #{status.distinct_thresholds_delivered} Air " <>
          "(runner minutes) notification thresholds this billing period and is on the " <>
          "#{account.plan_tier} plan. Usage at that level is typically where the enterprise " <>
          "plan starts making financial sense.",
      evidence: evidence,
      draft_subject: "Talk about enterprise for #{account_label}?",
      draft_body: draft_body(account_label, status.distinct_thresholds_delivered),
      contact_id: contact && contact.id,
      severity: "low",
      expires_in_days: 21
    }
  end

  defp draft_body(account_label, thresholds) do
    """
    Hi,

    Wanted to open a conversation about the enterprise plan for #{account_label}. \
    You've hit #{thresholds} usage-notification thresholds already this billing period, \
    which is usually where teams start paying more on the current plan than they would on \
    enterprise pricing.

    Happy to walk through the numbers together and see whether it makes sense to switch.

    Best,
    """
  end

  defp maybe_close_episode(%Account{} = account) do
    _ = Nudges.close_episode(account, @signal_name)
    :skip
  end

  defp account_label(%Account{name: name}) when is_binary(name) and name != "", do: name
  defp account_label(%Account{account_key: key}), do: key
end
