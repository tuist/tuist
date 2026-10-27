defmodule Atlas.Engineering.Alerts.Workers.DeliverRuleTest do
  use Atlas.DataCase, async: true
  use Mimic

  alias Atlas.Engineering.Alerts
  alias Atlas.Engineering.Alerts.Destinations.Slack, as: SlackDestination
  alias Atlas.Engineering.Alerts.Notification
  alias Atlas.Engineering.Alerts.Rule
  alias Atlas.Engineering.Alerts.Workers.DeliverRule
  alias Atlas.Engineering.Errors
  alias Atlas.Engineering.Errors.Issue
  alias Atlas.Engineering.Projects.Project
  alias Ecto.Adapters.SQL.Sandbox

  test "concurrent replicas cannot both deliver within a rule's cooldown" do
    parent = self()
    notifications = start_supervised!({Agent, fn -> [] end})
    rule = %Rule{id: Ecto.UUID.generate(), trigger: :event_rate, destination_type: :slack}
    issue = %Issue{id: Ecto.UUID.generate()}

    # Exercise real locks/connections without committing project fixtures that
    # would become visible to unrelated async list/count tests.
    stub(Alerts, :get_rule, fn _id -> {:ok, rule} end)
    stub(Errors, :fetch_issue, fn _id -> {:ok, issue} end)

    stub(Alerts, :in_cooldown?, fn _rule, _id ->
      send(parent, {:cooldown_checked, self()})
      Agent.get(notifications, &Enum.any?(&1, fn attrs -> attrs.status == "sent" end))
    end)

    stub(Alerts, :record_notification, fn attrs ->
      Agent.update(notifications, &[attrs | &1])
      {:ok, %Notification{}}
    end)

    expect(Repo, :query!, 3, fn sql, params ->
      send(parent, {:lock_attempt, self()})
      call_original(Repo, :query!, [sql, params])
    end)

    stub(SlackDestination, :deliver, fn _rule, _issue, _reason, _opts ->
      send(parent, {:delivery_started, self()})

      receive do
        :complete_delivery -> :ok
      after
        30_000 -> flunk("delivery was not released")
      end
    end)

    first = Task.async(fn -> Sandbox.unboxed_run(Repo, fn -> DeliverRule.perform(job(rule, issue)) end) end)
    first_pid = first.pid
    # Each independent worker must first check out a connection from the pool
    # shared by the async suite; checkout latency is not part of the lock contract.
    assert_receive {:lock_attempt, ^first_pid}, 10_000
    assert_receive {:cooldown_checked, ^first_pid}, 1_000
    assert_receive {:delivery_started, ^first_pid}, 1_000

    second = Task.async(fn -> Sandbox.unboxed_run(Repo, fn -> DeliverRule.perform(job(rule, issue)) end) end)
    second_pid = second.pid
    assert_receive {:lock_attempt, ^second_pid}, 10_000
    assert {:snooze, 10} = Task.await(second, 10_000)
    refute_receive {:cooldown_checked, ^second_pid}
    refute_receive {:delivery_started, ^second_pid}

    send(first_pid, :complete_delivery)
    assert :ok = Task.await(first, 10_000)

    retry = Task.async(fn -> Sandbox.unboxed_run(Repo, fn -> DeliverRule.perform(job(rule, issue)) end) end)
    retry_pid = retry.pid
    assert :ok = Task.await(retry, 10_000)
    assert_receive {:lock_attempt, ^retry_pid}
    assert_receive {:cooldown_checked, ^retry_pid}
    refute_receive {:delivery_started, ^retry_pid}
    assert Agent.get(notifications, &Enum.sort(Enum.map(&1, fn attrs -> attrs.status end))) == ["sent", "skipped"]
  end

  test "a failed attempt commits its notification and remains retryable" do
    {_project, rule, issue} = fixtures()
    expect(SlackDestination, :deliver, fn _rule, _issue, _reason, _opts -> {:error, :unavailable} end)
    assert {:error, :unavailable} = DeliverRule.perform(job(rule, issue))

    expect(SlackDestination, :deliver, fn _rule, _issue, _reason, _opts -> :ok end)
    assert :ok = DeliverRule.perform(job(rule, issue))

    notifications = Repo.all(from(n in Notification, where: n.rule_id == ^rule.id))
    assert Enum.sort(Enum.map(notifications, & &1.status)) == [:failed, :sent]
  end

  test "disabled rules do not call a destination" do
    {_project, rule, issue} = fixtures()
    Repo.update_all(from(r in Rule, where: r.id == ^rule.id), set: [enabled: false])
    stub(SlackDestination, :deliver, fn _rule, _issue, _reason, _opts -> flunk("disabled rule delivered") end)
    assert :ok = DeliverRule.perform(job(rule, issue))
  end

  test "a windowed spike sends signed, environment-scoped webhook evidence and observes cooldown" do
    {rule, issue} = spike_fixtures()
    parent = self()
    stub(Alerts, :spike_matches, fn _rule, _at, _opts -> {:ok, [%{issue_id: issue.id, event_count: 107}]} end)

    stub(Req, :post, fn _url, opts ->
      send(parent, {:webhook, opts[:headers], opts[:body]})
      {:ok, %Req.Response{status: 202}}
    end)

    job = %Oban.Job{
      args: %{"rule_id" => rule.id, "subject_id" => issue.id, "reason" => "event_spike", "environment" => "staging"}
    }

    assert :ok = DeliverRule.perform(job)
    assert_receive {:webhook, headers, encoded}
    body = JSON.decode!(encoded)
    assert body["environment"] == "prod"
    assert body["rule"]["tier"] == "incident"
    assert body["signal"]["event_count"] == 107
    assert body["signal"]["window_minutes"] == 5
    assert body["issue"]["event_count"] == 10
    assert body["grouping_key"] == "atlas:#{rule.id}:#{issue.id}:prod"
    signature = :crypto.mac(:hmac, :sha256, rule.webhook_signing_secret, encoded) |> Base.encode16(case: :lower)
    assert {"x-atlas-signature", "sha256=" <> signature} in headers

    assert :ok = DeliverRule.perform(job)
    refute_receive {:webhook, _, _}

    assert [%Notification{metadata: %{"signal" => %{"event_count" => 107}}}] =
             Repo.all(from(n in Notification, where: n.rule_id == ^rule.id and n.status == :sent))
  end

  test "stale spikes do not page and query failures remain retryable rather than healthy" do
    {rule, issue} = spike_fixtures()
    job = %Oban.Job{args: %{"rule_id" => rule.id, "subject_id" => issue.id, "reason" => "event_spike"}}
    stub(Req, :post, fn _, _ -> flunk("a stale or unqueryable spike must not send") end)

    stub(Alerts, :spike_matches, fn _, _, _ -> {:ok, []} end)
    assert :ok = DeliverRule.perform(job)

    stub(Alerts, :spike_matches, fn _, _, _ -> {:error, :spike_query_failed} end)
    assert {:error, :spike_query_failed} = DeliverRule.perform(job)
    assert Repo.all(from(n in Notification, where: n.rule_id == ^rule.id)) == []
  end

  test "changing a rule trigger invalidates queued cumulative and regression firings" do
    stub(SlackDestination, :deliver, fn _, _, _, _ -> flunk("a firing from the previous trigger must not send") end)

    for {previous, current} <- [{:event_rate, :regression}, {:regression, :event_rate}] do
      {_project, rule, issue} = fixtures()
      {:ok, rule} = Alerts.update_rule(rule, %{trigger: current})
      stale = %Oban.Job{args: %{"rule_id" => rule.id, "subject_id" => issue.id, "reason" => Atom.to_string(previous)}}

      assert :ok = DeliverRule.perform(stale)
      assert Repo.all(from(n in Notification, where: n.rule_id == ^rule.id)) == []
    end
  end

  defp spike_fixtures do
    {_project, rule, issue} = fixtures()

    {:ok, rule} =
      Alerts.update_rule(rule, %{
        trigger: :event_spike,
        tier: :incident,
        threshold_event_count: 100,
        threshold_window_minutes: 5,
        environment: "prod",
        min_level: :error,
        destination_type: :webhook,
        webhook_url: "https://receiver.example.org/private-integration"
      })

    {rule, issue}
  end

  defp job(rule, issue) do
    %Oban.Job{args: %{"rule_id" => rule.id, "subject_id" => issue.id, "reason" => "event_rate"}}
  end

  defp fixtures do
    project = Repo.insert!(Project.changeset(%Project{}, %{name: "alert-#{Ecto.UUID.generate()}"}))

    rule =
      Repo.insert!(
        Rule.changeset(%Rule{}, %{
          project_id: project.id,
          name: "Cooldown rule",
          trigger: :event_rate,
          destination_type: :slack,
          slack_channel_id: "test-channel",
          cooldown_minutes: 60
        })
      )

    now = DateTime.utc_now()

    issue =
      Repo.insert!(
        Issue.changeset(%Issue{}, %{
          project_id: project.id,
          fingerprint: Base.encode16(:crypto.strong_rand_bytes(32), case: :lower),
          title: "Concurrent error",
          first_seen: now,
          last_seen: now,
          event_count: 10
        })
      )

    {project, rule, issue}
  end
end
