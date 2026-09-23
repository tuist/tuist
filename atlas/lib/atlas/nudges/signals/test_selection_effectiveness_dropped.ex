defmodule Atlas.Nudges.Signals.TestSelectionEffectivenessDropped do
  @moduledoc """
  Fires when a paying customer's 7-day selective-testing skip rate has
  dropped below an absolute floor AND fallen by at least
  `@baseline_drop` versus their 28-day baseline. The pitch is a
  conversation about what changed so selective testing is skipping less.
  """

  import Ecto.Query

  alias Atlas.Accounts.Account
  alias Atlas.Nudges
  alias Atlas.Nudges.Analytics
  alias Atlas.Nudges.Proposal
  alias Atlas.Repo

  @signal_name "test_selection_effectiveness_dropped"
  @short_window 7
  @baseline_window 28
  @absolute_ceiling 0.40
  @baseline_drop 0.15

  def name, do: @signal_name

  def candidate_account_ids do
    Account
    |> where([a], not is_nil(a.plan_tier) and a.plan_tier != "free")
    |> where([a], is_nil(a.not_an_account_at))
    |> select([a], a.id)
    |> Repo.all()
  end

  def evaluate(%Account{} = account) do
    current = Analytics.selective_testing_effectiveness(account, window: @short_window)
    baseline = Analytics.selective_testing_effectiveness(account, window: @baseline_window)

    with :ok <- ready?(current),
         :ok <- ready?(baseline),
         true <- degraded?(current, baseline) do
      dispatch(account, current, baseline)
    else
      _not_degraded_or_not_ready -> maybe_close_episode(account)
    end
  end

  defp ready?(%Analytics.Reading{stage: :ok, ratio: ratio}) when not is_nil(ratio), do: :ok
  defp ready?(_reading), do: :skip

  defp degraded?(current, baseline) do
    current.ratio < @absolute_ceiling and baseline.ratio - current.ratio >= @baseline_drop
  end

  defp dispatch(%Account{} = account, current, baseline) do
    evidence = %{
      "current_ratio" => current.ratio,
      "current_numerator" => current.numerator,
      "current_denominator" => current.denominator,
      "baseline_ratio" => baseline.ratio,
      "baseline_numerator" => baseline.numerator,
      "baseline_denominator" => baseline.denominator,
      "short_window_days" => @short_window,
      "baseline_window_days" => @baseline_window,
      "absolute_ceiling" => @absolute_ceiling,
      "baseline_drop" => @baseline_drop
    }

    case Nudges.open_or_touch_episode(account, @signal_name, evidence) do
      {:existing, _episode} -> :skip
      {:opened, episode} -> {:ok, build_proposal(account, episode, current, baseline, evidence)}
      {:error, _reason} -> :skip
    end
  end

  defp build_proposal(%Account{} = account, episode, current, baseline, evidence) do
    contact = Nudges.select_contact_for(account)
    account_label = account_label(account)
    current_pct = format_percent(current.ratio)
    baseline_pct = format_percent(baseline.ratio)

    %Proposal{
      dedup_key: "#{@signal_name}:#{episode.id}",
      title: "#{account_label}: selective testing skipping #{current_pct} (was #{baseline_pct})",
      rationale:
        "Selective testing skipped #{current_pct} of eligible targets over the last " <>
          "#{@short_window} days, down from a #{@baseline_window}-day baseline of #{baseline_pct}. " <>
          "That is a lot of extra CI time. Something in the fingerprint changed, or the graph " <>
          "grew a hot dependency more targets depend on.",
      evidence: evidence,
      draft_subject: "Selective testing on #{account_label} skipping fewer targets",
      draft_body: draft_body(account_label, current_pct, baseline_pct),
      contact_id: contact && contact.id,
      severity: "normal",
      expires_in_days: 7
    }
  end

  defp draft_body(account_label, current_pct, baseline_pct) do
    """
    Hi,

    Noticed selective testing on #{account_label} is skipping #{current_pct} of eligible targets \
    over the last week, down from a four-week baseline of #{baseline_pct}. That's a chunk of \
    CI time worth digging into: usually a fingerprint change or a widened dependency chain.

    Happy to jump on a short call and look at it together.

    Best,
    """
  end

  defp maybe_close_episode(%Account{} = account) do
    _ = Nudges.close_episode(account, @signal_name)
    :skip
  end

  defp format_percent(ratio) when is_float(ratio), do: "#{round(ratio * 100)}%"
  defp format_percent(_ratio), do: "-"

  defp account_label(%Account{name: name}) when is_binary(name) and name != "", do: name
  defp account_label(%Account{account_key: key}), do: key
end
