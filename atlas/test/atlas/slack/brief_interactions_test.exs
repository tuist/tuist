defmodule Atlas.Slack.BriefInteractionsTest do
  use Atlas.DataCase, async: true

  alias Atlas.Briefs.Brief
  alias Atlas.Briefs.BriefItem
  alias Atlas.Briefs.Notifier
  alias Atlas.Briefs.Subscription
  alias Atlas.Slack.Interactions
  alias Atlas.Slack.User, as: SlackUser
  alias Atlas.Users.User

  test "resolves a Slack user id to an executive before changing a brief item" do
    executive = insert_user!(:executive)
    insert_slack_user!(executive)
    item = insert_item!()

    payload = %{
      "type" => "block_actions",
      "user" => %{"id" => "U-EXECUTIVE", "name" => "brief-executive"},
      "actions" => [
        %{"action_id" => Notifier.action_id("acknowledge"), "value" => item.id}
      ]
    }

    assert {:ok, message} = Interactions.handle_interaction(payload, :company)
    assert message =~ "Acknowledged"
    assert Repo.get!(BriefItem, item.id).status == "acknowledged"
  end

  test "rejects a matched Slack user who is not an executive" do
    employee = insert_user!(:employee)
    insert_slack_user!(employee)
    item = insert_item!()

    payload = %{
      "type" => "block_actions",
      "user" => %{"id" => "U-EMPLOYEE", "name" => "brief-employee"},
      "actions" => [
        %{"action_id" => Notifier.action_id("mute"), "value" => item.id}
      ]
    }

    assert {:error, "Leadership brief actions require an executive role."} =
             Interactions.handle_interaction(payload, :company)

    assert Repo.get!(BriefItem, item.id).status == "open"
  end

  defp insert_user!(role) do
    %User{}
    |> User.changeset(%{
      email: "brief-#{role}-#{System.unique_integer([:positive])}@example.com",
      name: "Brief #{role}",
      role: role
    })
    |> Repo.insert!()
  end

  defp insert_slack_user!(user) do
    slack_user_id = if user.role == :executive, do: "U-EXECUTIVE", else: "U-EMPLOYEE"

    %SlackUser{slack_app: :company}
    |> SlackUser.changeset(%{
      slack_user_id: slack_user_id,
      name: "brief-#{user.role}",
      email: user.email
    })
    |> Repo.insert!()
  end

  defp insert_item! do
    subscription =
      %Subscription{}
      |> Subscription.changeset(%{
        label: "Leadership daily",
        audience_key: "leadership-#{System.unique_integer([:positive])}",
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
      detail: "The next customer conversation is not scheduled.",
      severity: "warning",
      sensitivity: "internal",
      materiality_score: Decimal.new("0.82"),
      fingerprint: "accounts:renewal:#{System.unique_integer([:positive])}",
      position: 0,
      status: "open"
    })
    |> Repo.insert!()
  end
end
