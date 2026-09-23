defmodule Atlas.Nudges.Signals.ActivationStalled do
  @moduledoc """
  Fires when a paying account has been around long enough that we would
  expect any Tuist activity, and we have observed none across the tracked
  features. Suppresses when we could not measure the account at all (no
  metric buckets have ever landed either), so a resolution failure never
  masquerades as a stalled onboarding.
  """

  import Ecto.Query

  alias Atlas.Accounts.Account
  alias Atlas.Nudges
  alias Atlas.Nudges.Analytics.FeatureFirstSeen
  alias Atlas.Nudges.Analytics.MetricBucket
  alias Atlas.Nudges.Proposal
  alias Atlas.Repo

  @signal_name "activation_stalled"
  @grace_days 7

  def name, do: @signal_name

  def candidate_account_ids do
    cutoff =
      DateTime.utc_now()
      |> DateTime.add(-@grace_days * 86_400, :second)
      |> DateTime.truncate(:second)

    Account
    |> where([a], not is_nil(a.plan_tier) and a.plan_tier != "free")
    |> where([a], is_nil(a.not_an_account_at))
    |> where([a], a.inserted_at <= ^cutoff)
    |> select([a], a.id)
    |> Repo.all()
  end

  def evaluate(%Account{} = account) do
    cond do
      has_any_first_seen?(account.id) -> maybe_close_episode(account)
      not measurement_ok?(account.id) -> :skip
      true -> dispatch(account)
    end
  end

  defp has_any_first_seen?(account_id) do
    Repo.exists?(from f in FeatureFirstSeen, where: f.account_id == ^account_id)
  end

  # We treat an account as measurable once at least one `refresh_status=ok`
  # bucket has ever landed. This keeps a resolution failure (never wrote a
  # bucket at all, or only ever wrote failed ones) from firing the signal.
  defp measurement_ok?(account_id) do
    Repo.exists?(from b in MetricBucket, where: b.account_id == ^account_id and b.refresh_status == "ok")
  end

  defp dispatch(%Account{} = account) do
    evidence = %{
      "signup_at" => account.inserted_at |> NaiveDateTime.to_iso8601(),
      "grace_days" => @grace_days
    }

    case Nudges.open_or_touch_episode(account, @signal_name, evidence) do
      {:existing, _episode} -> :skip
      {:opened, episode} -> {:ok, build_proposal(account, episode, evidence)}
      {:error, _reason} -> :skip
    end
  end

  defp build_proposal(%Account{} = account, episode, evidence) do
    contact = Nudges.select_contact_for(account)
    account_label = account_label(account)

    %Proposal{
      dedup_key: "#{@signal_name}:#{episode.id}",
      title: "#{account_label}: no Tuist activity #{@grace_days}+ days after sign-up",
      rationale:
        "#{account_label} signed up more than #{@grace_days} days ago and we have observed no " <>
          "activity across cache, builds, tests, or any other tracked feature. Worth a short " <>
          "check-in to see what is blocking setup.",
      evidence: evidence,
      draft_subject: "Setup help for #{account_label}?",
      draft_body: draft_body(account_label),
      contact_id: contact && contact.id,
      severity: "normal",
      expires_in_days: 14
    }
  end

  defp draft_body(account_label) do
    """
    Hi,

    Noticed the #{account_label} Tuist account has not seen activity yet since sign-up. \
    That is usually a sign of something in the setup that would help to walk through together.

    Happy to jump on a quick call and get you unblocked.

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
