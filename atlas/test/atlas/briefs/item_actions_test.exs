defmodule Atlas.Briefs.ItemActionsTest do
  use Atlas.DataCase, async: true
  use Oban.Testing, repo: Atlas.Repo

  alias Atlas.Audit.Activity
  alias Atlas.Briefs.Brief
  alias Atlas.Briefs.BriefItem
  alias Atlas.Briefs.ItemActions
  alias Atlas.Briefs.Subscription
  alias Atlas.Briefs.Suppression
  alias Atlas.Briefs.Workers.RefreshBriefMessage
  alias Atlas.Users.User

  test "claiming and completing an item records ownership, a result, a cooldown, and audit history" do
    item = insert_item!()
    actor = insert_user!()

    assert {:ok, claimed} = ItemActions.claim(item, actor)
    assert claimed.owner_id == actor.id
    assert claimed.status == "acknowledged"

    assert {:ok, completed} = ItemActions.complete(claimed, "The renewal call is booked.", actor)
    assert completed.status == "completed"
    assert completed.resolution_note == "The renewal call is booked."
    assert completed.resolved_by_id == actor.id

    assert %Suppression{reason: "Completed item cooldown", brief_subscription_id: subscription_id} =
             Repo.get_by(Suppression, domain: item.domain, fingerprint: item.fingerprint)

    assert subscription_id == Repo.get!(Brief, item.brief_id).brief_subscription_id

    assert Repo.exists?(
             from activity in Activity,
               where:
                 activity.action == "brief_item.completed" and
                   activity.target_id == ^item.id and activity.actor_id == ^actor.id
           )

    assert_enqueued(worker: RefreshBriefMessage, args: %{"brief_id" => item.brief_id})
  end

  test "not useful feedback creates a short suppression through the Slack action" do
    item = insert_item!()
    actor = insert_user!()

    assert {:ok, %{message: message}} =
             ItemActions.handle_slack_action("not_useful", item.id,
               actor_email: actor.email,
               interface: "slack"
             )

    assert message =~ "muted for 14 days"

    stored = Repo.get!(BriefItem, item.id)
    assert stored.usefulness == "not_useful"
    assert stored.status == "suppressed"
    assert %Suppression{reason: "Not useful"} = Repo.get_by(Suppression, fingerprint: item.fingerprint)
  end

  test "Slack actions require a matched executive" do
    item = insert_item!()

    employee =
      %User{}
      |> User.changeset(%{
        email: "brief-employee-#{System.unique_integer([:positive])}@example.com",
        name: "Brief Employee",
        role: :employee
      })
      |> Repo.insert!()

    assert {:error, :brief_item_actor_required} = ItemActions.handle_slack_action("mute", item.id)

    assert {:error, :brief_item_executive_required} =
             ItemActions.handle_slack_action("mute", item.id, actor_email: employee.email)

    assert Repo.get!(BriefItem, item.id).status == "open"
  end

  test "suppressions are scoped to each brief audience" do
    fingerprint = "accounts:shared-risk"
    first = insert_item!(audience_key: "leadership-one", fingerprint: fingerprint)
    second = insert_item!(audience_key: "leadership-two", fingerprint: fingerprint)
    actor = insert_user!()

    assert {:ok, _item} = ItemActions.suppress(first, "Muted by first audience", 30, actor)
    assert {:ok, _item} = ItemActions.suppress(second, "Muted by second audience", 30, actor)

    assert Repo.aggregate(
             from(suppression in Suppression,
               where: suppression.domain == "accounts" and suppression.fingerprint == ^fingerprint
             ),
             :count
           ) == 2
  end

  test "completion requires a durable result" do
    item = insert_item!()
    assert {:error, :resolution_note_required} = ItemActions.complete(item, "   ")
    assert Repo.get!(BriefItem, item.id).status == "open"
  end

  defp insert_item!(opts \\ []) do
    # `brief_subscriptions` is uniquely indexed on `(audience_key, cadence)`, so
    # even the keys a caller names have to belong to one test.
    audience_key = "#{Keyword.get(opts, :audience_key, "leadership")}-#{System.unique_integer([:positive])}"
    fingerprint = Keyword.get(opts, :fingerprint, "accounts:renewal:#{System.unique_integer([:positive])}")

    subscription =
      %Subscription{}
      |> Subscription.changeset(%{
        label: "Leadership daily",
        audience_key: audience_key,
        cadence: "daily",
        domains: ["accounts"],
        slack_app: "company",
        slack_channel_id: "C-LEADERSHIP",
        max_sensitivity: "restricted",
        attention_budget: 8,
        enabled: true
      })
      |> Repo.insert!()

    brief =
      %Brief{brief_subscription_id: subscription.id}
      |> Brief.changeset(%{
        cadence: "daily",
        period_start: ~U[2026-07-20 00:00:00Z],
        period_end: ~U[2026-07-21 00:00:00Z],
        status: "material",
        headline: "Daily leadership brief",
        attention_budget: 8,
        sensitivity: "internal",
        generation_mode: "deterministic"
      })
      |> Repo.insert!()

    %BriefItem{brief_id: brief.id}
    |> BriefItem.changeset(%{
      domain: "accounts",
      kind: "follow_up",
      title: "Book the renewal call",
      detail: "The term ends soon and the next conversation is not scheduled.",
      severity: "warning",
      sensitivity: "internal",
      materiality_score: Decimal.new("0.82"),
      suggested_action: "Book the renewal call.",
      completion_condition: "The call is on the calendar.",
      fingerprint: fingerprint,
      position: 0,
      status: "open"
    })
    |> Repo.insert!()
  end

  defp insert_user! do
    %User{}
    |> User.changeset(%{
      email: "brief-owner-#{System.unique_integer([:positive])}@example.com",
      name: "Brief Owner",
      role: :executive
    })
    |> Repo.insert!()
  end
end
