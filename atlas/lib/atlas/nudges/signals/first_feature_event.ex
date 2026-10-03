defmodule Atlas.Nudges.Signals.FirstFeatureEvent do
  @moduledoc """
  Shared implementation for the "first X event" signal family
  (`first_cache_event`, `first_build_event`, `first_test_event`).

  Fires once per `(account, feature)` when
  `Atlas.Nudges.Analytics.FeatureFirstSeen` records a fresh row for that
  pairing (i.e. we detected the account's first-ever activity for that
  feature). Skipped forever after the episode is opened; the episode is
  never closed, because "first use" is a one-time transition.
  """

  import Ecto.Query

  alias Atlas.Accounts.Account
  alias Atlas.Nudges
  alias Atlas.Nudges.Analytics.FeatureFirstSeen
  alias Atlas.Nudges.Proposal
  alias Atlas.Repo

  # A first-seen row is "fresh" when it landed within this many hours.
  # That gives the daily FeatureFirstSeen worker up to two days of slack
  # before we would miss the transition entirely; after that, the account
  # has quietly been using the feature for a while and we say nothing.
  @fresh_hours 48

  def name(feature), do: "first_#{feature_slug_for_name(feature)}_event"

  def candidate_account_ids do
    Account
    |> where([a], not is_nil(a.plan_tier) and a.plan_tier != "free")
    |> where([a], is_nil(a.not_an_account_at))
    |> select([a], a.id)
    |> Repo.all()
  end

  def evaluate(%Account{} = account, feature, opts \\ []) do
    cutoff = DateTime.utc_now() |> DateTime.add(-@fresh_hours, :hour) |> DateTime.truncate(:second)

    row =
      Repo.one(
        from f in FeatureFirstSeen,
          where: f.account_id == ^account.id and f.feature == ^feature
      )

    case row do
      %FeatureFirstSeen{first_seen_computed_at: computed_at} = fresh ->
        if DateTime.after?(computed_at, cutoff) do
          dispatch(account, feature, fresh, opts)
        else
          :skip
        end

      nil ->
        :skip
    end
  end

  defp dispatch(%Account{} = account, feature, %FeatureFirstSeen{} = row, opts) do
    signal_name = name(feature)

    evidence = %{
      "feature" => feature,
      "first_use_at" => row.first_use_at |> DateTime.to_iso8601(),
      "first_seen_computed_at" => row.first_seen_computed_at |> DateTime.to_iso8601()
    }

    case Nudges.open_or_touch_episode(account, signal_name, evidence) do
      {:existing, _episode} -> :skip
      {:opened, episode} -> {:ok, build_proposal(account, signal_name, feature, episode, evidence, opts)}
      {:error, _reason} -> :skip
    end
  end

  defp build_proposal(%Account{} = account, signal_name, feature, episode, evidence, opts) do
    contact = Nudges.select_contact_for(account)
    account_label = account_label(account)
    label = Keyword.get(opts, :label, feature)
    walkthrough = Keyword.get(opts, :walkthrough, "Happy to jump on a call to walk through what to watch.")

    %Proposal{
      dedup_key: "#{signal_name}:#{episode.id}",
      title: "#{account_label}: first #{label} activity",
      rationale:
        "We just observed the first #{label} activity on #{account_label}. This is a good " <>
          "moment for a short walkthrough of what to watch and how to get the most out of it.",
      evidence: evidence,
      draft_subject: "Welcome to Tuist #{label} for #{account_label}",
      draft_body: draft_body(account_label, label, walkthrough),
      contact_id: contact && contact.id,
      severity: "low",
      expires_in_days: 14
    }
  end

  defp draft_body(account_label, label, walkthrough) do
    """
    Hi,

    Saw the first #{label} activity on the #{account_label} Tuist account come through. \
    Wanted to open the door for a short walkthrough: what to watch, how to spot regressions early, \
    and where the biggest wins usually come from.

    #{walkthrough}

    Best,
    """
  end

  defp feature_slug_for_name("test_analytics"), do: "test"
  defp feature_slug_for_name("builds"), do: "build"
  defp feature_slug_for_name(other), do: other

  defp account_label(%Account{name: name}) when is_binary(name) and name != "", do: name
  defp account_label(%Account{account_key: key}), do: key
end
