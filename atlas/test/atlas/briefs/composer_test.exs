defmodule Atlas.Briefs.ComposerTest do
  use Atlas.DataCase, async: true
  use Mimic
  use Oban.Testing, repo: Atlas.Repo

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Outcome
  alias Atlas.Briefs.Brief
  alias Atlas.Briefs.Composer
  alias Atlas.Briefs.ItemActions
  alias Atlas.Briefs.Subscription
  alias Atlas.Finance.Briefs.Adapter
  alias Atlas.Integrations
  alias Atlas.Product
  alias Atlas.Slack.Channel

  # `slack_channels.channel_id` is unique across the table, so the channel this
  # module syncs has to be its own. Tests inside a module run one at a time, so a
  # module-wide id cannot contend with itself the way a suite-wide one does.
  @slack_channel_id "C-COMPOSER"

  test "reuses the one combined brief for a subscription cadence and period" do
    subscription = insert_subscription!()
    period = %{start_at: ~U[2026-07-13 00:00:00Z], end_at: ~U[2026-07-20 00:00:00Z]}

    assert {:ok, first} = Composer.compose(subscription, period: period, now: period.end_at)
    assert {:ok, second} = Composer.compose(subscription, period: period, now: period.end_at)

    assert second.id == first.id

    assert Repo.aggregate(
             from(brief in Brief,
               where:
                 brief.brief_subscription_id == ^subscription.id and brief.cadence == "daily" and
                   brief.period_start == ^period.start_at
             ),
             :count
           ) == 1
  end

  test "persists the agent narrative and headline even when there are no action items" do
    subscription = insert_subscription!("narrative-#{System.unique_integer([:positive])}", ["finance"])
    period = %{start_at: ~U[2026-07-20 00:00:00Z], end_at: ~U[2026-07-21 00:00:00Z]}

    report = %{
      "kind" => "finance_pulse",
      "headline" => "Hardware drove this week's spending",
      "intro" => "Cash remains stable.",
      "drivers" => [%{"title" => "Hardware", "detail" => "One purchase explains the increase."}],
      "concerns" => [],
      "next_steps" => ["Confirm the purchase is a one-off."]
    }

    expect(Adapter, :candidate_items, fn "daily", ^period ->
      {:ok,
       %{
         summary: report["intro"],
         report: report,
         items: [],
         generation_mode: "agent",
         generated_by_agent: "weekly_summary_agent"
       }}
    end)

    assert {:ok, brief} = Composer.compose(subscription, period: period, now: period.end_at)
    stored = Repo.get!(Brief, brief.id)
    assert stored.report == report
    assert stored.headline == report["headline"]
    assert stored.summary == report["intro"]
    assert stored.status == "material"
    assert stored.generation_mode == "agent"
  end

  test "uses the full calendar month for a monthly recap" do
    assert Composer.period("monthly", ~U[2026-08-31 17:00:00Z]) == %{
             start_at: ~U[2026-08-01 00:00:00Z],
             end_at: ~U[2026-09-01 00:00:00Z]
           }
  end

  test "one audience's suppression does not hide the same trace from another audience" do
    first_subscription = insert_subscription!("leadership-one")
    second_subscription = insert_subscription!("leadership-two")
    insert_stale_pull_request!()

    first_period = %{start_at: ~U[2026-07-20 00:00:00Z], end_at: ~U[2026-07-21 00:00:00Z]}
    second_period = %{start_at: ~U[2026-07-21 00:00:00Z], end_at: ~U[2026-07-22 00:00:00Z]}

    assert {:ok, %{items: [first_item]}} =
             Composer.compose(first_subscription, period: first_period, now: first_period.end_at)

    assert {:ok, %{items: [_second_item]}} =
             Composer.compose(second_subscription, period: first_period, now: first_period.end_at)

    assert {:ok, _suppressed} = ItemActions.suppress(first_item, "Muted for one audience", 30)

    assert {:ok, %{items: []}} =
             Composer.compose(first_subscription, period: second_period, now: second_period.end_at)

    assert {:ok, %{items: [_visible]}} =
             Composer.compose(second_subscription, period: second_period, now: second_period.end_at)
  end

  test "customer outcomes no longer produce leadership brief items" do
    subscription = insert_subscription!("leadership-escalation", ["accounts"])
    _outcome = insert_outcome!("at_risk")

    first = %{start_at: ~U[2026-07-20 00:00:00Z], end_at: ~U[2026-07-21 00:00:00Z]}

    assert {:ok, %{items: []}} = Composer.compose(subscription, period: first, now: first.end_at)
  end

  test "composing fails loudly when the Slack channel has never been synced" do
    subscription =
      %Subscription{}
      |> Subscription.changeset(%{
        label: "Leadership daily",
        audience_key: "leadership-unsynced-#{System.unique_integer([:positive])}",
        cadence: "daily",
        domains: ["product"],
        slack_app: "company",
        slack_channel_id: "C-NEVER-SYNCED",
        max_sensitivity: "restricted",
        attention_budget: 8,
        enabled: true
      })
      |> Repo.insert!()

    period = %{start_at: ~U[2026-07-20 00:00:00Z], end_at: ~U[2026-07-21 00:00:00Z]}

    assert {:error, :slack_channel_not_synced} =
             Composer.compose(subscription, period: period, now: period.end_at)
  end

  defp insert_outcome!(health) do
    account =
      %Account{}
      |> Account.changeset(%{
        account_key: "account:#{System.unique_integer([:positive])}",
        name: "Northstar",
        segment: :customer
      })
      |> Repo.insert!()

    %Outcome{account_id: account.id}
    |> Outcome.changeset(%{
      account_id: account.id,
      title: "Reach adoption target",
      motion: "adoption",
      status: "active",
      health: health,
      success_measure: "Weekly active developers",
      reviewed_at: ~U[2026-07-19 00:00:00Z]
    })
    |> Repo.insert!()
  end

  defp insert_subscription!(audience_key \\ "leadership", domains \\ ["product"]) do
    channel =
      Repo.get_by(Channel, slack_app: :company, channel_id: @slack_channel_id) ||
        %Channel{slack_app: :company}
        |> Channel.changeset(%{channel_id: @slack_channel_id, channel_name: "leadership"})
        |> Repo.insert!()

    %Subscription{}
    |> Subscription.changeset(%{
      label: "Leadership weekly",
      # `brief_subscriptions` is uniquely indexed on `(audience_key, cadence)`.
      # Callers keep passing readable keys; the suffix is what makes the pair
      # belong to one test.
      audience_key: "#{audience_key}-#{System.unique_integer([:positive])}",
      cadence: "daily",
      domains: domains,
      slack_app: "company",
      slack_channel_id: channel.channel_id,
      max_sensitivity: "restricted",
      attention_budget: 8,
      enabled: true
    })
    |> Repo.insert!()
  end

  defp insert_stale_pull_request! do
    {:ok, app} =
      Integrations.create_github_app(%{
        name: "Composer product app",
        webhook_secret: "secret",
        app_id: "composer-#{System.unique_integer([:positive])}",
        private_key: "private-key",
        installation_id: "composer-#{System.unique_integer([:positive])}"
      })

    {:ok, repository} = Integrations.add_github_repository(app, %{owner: "tuist", repo: "atlas"})

    {:ok, _trace} =
      Product.record_trace(%{
        provider: "github",
        kind: "pull_request_opened",
        external_id: "pull_request:#{System.unique_integer([:positive])}:pull_request_opened",
        github_repository_id: repository.id,
        repository_full_name: "tuist/atlas",
        number: 42,
        title: "Review the coordination system",
        url: "https://github.com/tuist/atlas/pull/42",
        author_login: "octocat",
        occurred_at: ~U[2026-07-01 10:00:00Z],
        labels: [],
        sensitivity: "internal"
      })
  end
end
