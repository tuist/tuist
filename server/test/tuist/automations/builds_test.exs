defmodule Tuist.Automations.BuildsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Automations
  alias Tuist.Automations.ActionExecutor
  alias Tuist.Automations.Alerts.Alert
  alias Tuist.Automations.Builds
  alias Tuist.Automations.Builds.CacheKeyMonitor
  alias Tuist.Automations.Builds.Finding
  alias Tuist.Automations.Workers.BuildAlertEvaluationWorker
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    project = ProjectsFixtures.project_fixture(build_system: :gradle)

    {:ok, alert} =
      Automations.create_alert(%{
        project_id: project.id,
        name: "Cache key consistency",
        monitor_type: "cache_key_consistency",
        trigger_actions: [%{"type" => "send_slack", "channel" => "C1", "message" => "{{build.summary}}"}]
      })

    stub(CacheKeyMonitor, :commits, fn _, _, cursor, _, _, _ -> if cursor == "", do: ["commit"], else: [] end)
    %{project: project, alert: alert}
  end

  test "build rules accept only Slack actions, no test options and no automatic recovery", %{alert: alert} do
    assert Alert.changeset(alert, %{}).valid?
    refute Alert.changeset(alert, %{trigger_actions: [%{"type" => "add_label", "label" => "flaky"}]}).valid?
    refute Alert.changeset(alert, %{trigger_config: %{"threshold" => 1}}).valid?
    refute Alert.changeset(alert, %{recovery_enabled: true}).valid?
  end

  test "findings deduplicate across commits, repeated keys and reversed build order", %{alert: alert} do
    evidence = evidence()
    Builds.persist(alert, [evidence, evidence])
    Builds.persist(alert, [%{evidence | commit_sha: "later", first_key: "b", second_key: "a"}])
    assert [%{evidence: %{"commit_sha" => "commit"}}] = Builds.list_findings(alert.id)
  end

  test "grouped delivery checkpoints after success and does not resend recurring units", %{alert: alert} do
    Builds.persist(alert, [evidence(), %{evidence() | unit_key: "second", unit_name: "Other"}])

    expect(ActionExecutor, :execute_actions, fn _actions, current, %{type: :build_findings, findings: findings} ->
      assert current.id == alert.id
      assert length(findings) == 2
      :ok
    end)

    assert :ok = Builds.notify_pending(alert)
    assert :ok = Builds.notify_pending(alert)
    assert Enum.all?(Builds.list_findings(alert.id), & &1.notified_at)
  end

  test "failed delivery remains pending and can be retried", %{alert: alert} do
    Builds.persist(alert, [evidence()])
    expect(ActionExecutor, :execute_actions, fn _, _, _ -> {:error, :slack_unavailable} end)
    assert {:error, :slack_unavailable} = Builds.notify_pending(alert)
    assert [%{notified_at: nil}] = Builds.list_findings(alert.id)
    expect(ActionExecutor, :execute_actions, fn _, _, _ -> :ok end)
    assert :ok = Builds.notify_pending(alert)
    assert [%{notified_at: notified_at}] = Builds.list_findings(alert.id)
    assert notified_at
  end

  test "disabled rules do not deliver pending findings", %{alert: alert} do
    Builds.persist(alert, [evidence()])
    {:ok, _} = Automations.update_alert(alert, %{enabled: false})
    reject(ActionExecutor, :execute_actions, 3)
    assert :ok = Builds.notify_pending(alert)
    assert [%{notified_at: nil}] = Builds.list_findings(alert.id)
  end

  test "deleting a rule cascades its findings", %{alert: alert} do
    Builds.persist(alert, [evidence()])
    assert {:ok, _} = Automations.delete_alert(alert)
    assert Repo.all(Finding) == []
  end

  test "scheduled worker dispatches build monitor without a test baseline", %{alert: alert, project: project} do
    expect(CacheKeyMonitor, :page, fn id, "gradle", "", _cutoff, opts ->
      assert opts[:commit] == "commit"
      assert id == project.id
      [evidence()]
    end)

    expect(ActionExecutor, :execute_actions, fn _, _, %{type: :build_findings} -> :ok end)
    assert :ok = perform_job(BuildAlertEvaluationWorker, %{alert_id: alert.id})
    assert [%{notified_at: at}] = Builds.list_findings(alert.id)
    assert at
    assert {:ok, %{baseline_established_at: nil}} = Automations.get_alert(alert.id)
  end

  test "concurrent evaluations snooze instead of delivering twice", %{alert: alert} do
    config = Keyword.take(Repo.config(), [:hostname, :port, :username, :password, :database, :socket_dir, :ssl])
    {:ok, connection} = Postgrex.start_link(config)

    try do
      Postgrex.query!(connection, "SELECT pg_advisory_lock(hashtextextended($1, 0))", ["build-automation:#{alert.id}"])
      assert {:snooze, 30} = perform_job(BuildAlertEvaluationWorker, %{alert_id: alert.id})
    after
      GenServer.stop(connection)
    end
  end

  test "collects both Xcode cache sources before sending one grouped notification", %{alert: alert, project: project} do
    project |> Ecto.Changeset.change(build_system: :xcode) |> Repo.update!()
    expect(CacheKeyMonitor, :page, fn _, "xcode_module", "", _, _ -> [%{evidence() | source: "xcode_module"}] end)

    expect(CacheKeyMonitor, :page, fn _, "xcode_compilation", "", _, _ ->
      [%{evidence() | source: "xcode_compilation"}]
    end)

    expect(ActionExecutor, :execute_actions, fn _, _, %{findings: findings} ->
      assert length(findings) == 2
      :ok
    end)

    assert :ok = perform_job(BuildAlertEvaluationWorker, %{alert_id: alert.id})
  end

  test "a large backlog produces one notification and checkpoints only the claimed batch", %{alert: alert} do
    Builds.persist(alert, for(n <- 1..150, do: %{evidence() | unit_key: "unit-#{n}"}))

    expect(ActionExecutor, :execute_actions, fn _, _, %{finding_count: 150, findings: samples} ->
      assert length(samples) == 3
      Builds.persist(alert, [%{evidence() | unit_key: "arrived-during-delivery"}])
      :ok
    end)

    assert :ok = Builds.notify_pending(alert)
    assert Repo.aggregate(from(f in Finding, where: f.alert_id == ^alert.id and is_nil(f.notified_at)), :count) == 1
  end

  test "revoked destinations retain pending evidence without job retry loops", %{alert: alert} do
    Builds.persist(alert, [evidence()])
    expect(ActionExecutor, :execute_actions, fn _, _, _ -> {:error, :webhook_revoked} end)
    assert :ok = Builds.notify_pending(alert)
    assert [%{notified_at: nil}] = Builds.list_findings(alert.id)
  end

  test "backfills resume at the durable commit checkpoint and send a single summary", %{alert: alert} do
    commits = for n <- 1..11, do: "commit-#{n |> Integer.to_string() |> String.pad_leading(2, "0")}"
    expect(CacheKeyMonitor, :commits, fn _, _, "", _, _, _ -> commits end)

    stub(CacheKeyMonitor, :page, fn _, _, _, _, opts ->
      [%{evidence() | unit_key: opts[:commit], commit_sha: opts[:commit]}]
    end)

    expect(ActionExecutor, :execute_actions, fn _, _, %{finding_count: 11} -> :ok end)
    assert {:snooze, delay} = perform_job(BuildAlertEvaluationWorker, %{alert_id: alert.id})
    assert delay in 1..5
    {:ok, checkpoint} = Automations.get_alert(alert.id)
    assert checkpoint.build_scan_state["gradle"]["cursor"] == "commit-10"
    expect(CacheKeyMonitor, :commits, fn _, _, "commit-10", _, _, _ -> ["commit-11"] end)
    assert :ok = perform_job(BuildAlertEvaluationWorker, %{alert_id: alert.id})
    {:ok, completed} = Automations.get_alert(alert.id)
    refute Map.has_key?(completed.build_scan_state["gradle"], "until")
    assert completed.build_scan_state["gradle"]["full_completed_at"]
    {:ok, edited} = Automations.update_alert(alert, %{name: "Renamed"})
    assert edited.build_scan_state == completed.build_scan_state
  end

  test "a daily full sweep catches late telemetry outside the incremental overlap", %{alert: alert} do
    prior = DateTime.to_iso8601(DateTime.add(DateTime.utc_now(), -2, :day))

    Repo.update_all(from(a in Alert, where: a.id == ^alert.id),
      set: [build_scan_state: %{"gradle" => %{"full_completed_at" => prior, "completed_at" => prior}}]
    )

    expect(CacheKeyMonitor, :commits, fn _, _, "", cutoff, since, _ ->
      assert DateTime.diff(since, cutoff) < 1
      []
    end)

    assert :ok = perform_job(BuildAlertEvaluationWorker, %{alert_id: alert.id})
  end

  test "query failure advances the checkpoint without blocking later commits", %{alert: alert} do
    expect(CacheKeyMonitor, :commits, fn _, _, _, _, _, _ -> ["bad", "good"] end)

    expect(CacheKeyMonitor, :page, fn _, _, "", _, opts ->
      assert opts[:commit] == "bad"
      raise Ch.Error, message: "Query limit", code: 159
    end)

    expect(CacheKeyMonitor, :page, fn _, _, "", _, opts ->
      assert opts[:commit] == "good"
      [evidence()]
    end)

    expect(ActionExecutor, :execute_actions, fn _, _, %{finding_count: 1} -> :ok end)
    assert :ok = perform_job(BuildAlertEvaluationWorker, %{alert_id: alert.id})
    {:ok, current} = Automations.get_alert(alert.id)
    assert current.build_scan_state["gradle"]["skipped_commits"] == 1
  end

  test "connection outages retry without marking the baseline complete", %{alert: alert} do
    expect(CacheKeyMonitor, :page, fn _, _, _, _, _ -> raise DBConnection.ConnectionError, message: "Offline" end)
    assert_raise DBConnection.ConnectionError, fn -> Builds.evaluate(alert) end
    {:ok, current} = Automations.get_alert(alert.id)
    refute current.build_scan_state["gradle"]["full_completed_at"]
    assert current.build_scan_state["gradle"]["skipped_commits"] == 0
  end

  test "resumes a partially paged commit even if parent metadata is no longer eligible", %{alert: alert} do
    now = DateTime.to_iso8601(DateTime.utc_now())
    since = DateTime.to_iso8601(DateTime.add(DateTime.utc_now(), -30, :day))

    state = %{
      "cursor" => "",
      "active_commit" => "commit",
      "identity_cursor" => "saved-unit",
      "until" => now,
      "since" => since,
      "full" => true
    }

    Repo.update_all(from(a in Alert, where: a.id == ^alert.id), set: [build_scan_state: %{"gradle" => state}])
    expect(CacheKeyMonitor, :commits, fn _, _, _, _, _, _ -> [] end)

    expect(CacheKeyMonitor, :page, fn _, _, "saved-unit", _, opts ->
      assert opts[:commit] == "commit"
      [evidence()]
    end)

    expect(ActionExecutor, :execute_actions, fn _, _, _ -> :ok end)
    assert :ok = perform_job(BuildAlertEvaluationWorker, %{alert_id: alert.id})
  end

  test "source-native links and unsupported systems remain explicit" do
    assert Builds.run_path("bazel", "id") == "/builds/invocations/id"
    assert Builds.run_path("once", "id") == "/once/runs/id"
    assert Builds.run_path("xcode_module", "id") == "/runs/id"
    refute Builds.supported?(%{build_system: :mix})
  end

  defp evidence do
    %{
      source: "gradle",
      unit_key: "[root,compile,Compile]",
      unit_name: "compile",
      commit_sha: "commit",
      first_key: "a",
      first_run: UUIDv7.generate(),
      second_key: "b",
      second_run: UUIDv7.generate()
    }
  end
end
