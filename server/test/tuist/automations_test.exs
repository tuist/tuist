defmodule Tuist.AutomationsTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Automations
  alias Tuist.Automations.ActionExecutor
  alias Tuist.Automations.Alerts.Alert
  alias Tuist.Automations.IssueLink
  alias TuistTestSupport.Fixtures.AutomationsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.VCSFixtures

  describe "list_alerts/1" do
    test "returns automations for the given project ordered by insertion time" do
      project = ProjectsFixtures.project_fixture()
      other_project = ProjectsFixtures.project_fixture()
      first = AutomationsFixtures.automation_alert_fixture(project: project, name: "first")
      _other = AutomationsFixtures.automation_alert_fixture(project: other_project)
      second = AutomationsFixtures.automation_alert_fixture(project: project, name: "second")

      ids = project.id |> Automations.list_alerts() |> Enum.map(& &1.id)
      assert ids == [first.id, second.id]
    end

    test "returns an empty list when project has no automations" do
      project = ProjectsFixtures.project_fixture()
      assert Automations.list_alerts(project.id) == []
    end

    test "returns the seeded default alert when the fixture keeps it" do
      project = ProjectsFixtures.project_fixture(with_default_alert: true)
      assert [%{name: "Flaky test detection"}] = Automations.list_alerts(project.id)
    end
  end

  describe "get_alert/1" do
    test "returns the automation when found" do
      automation = AutomationsFixtures.automation_alert_fixture()
      assert {:ok, fetched} = Automations.get_alert(automation.id)
      assert fetched.id == automation.id
    end

    test "returns :not_found when missing" do
      assert {:error, :not_found} = Automations.get_alert(UUIDv7.generate())
    end
  end

  describe "create_alert/1" do
    test "inserts a valid automation" do
      project = ProjectsFixtures.project_fixture()

      attrs = %{
        "project_id" => project.id,
        "name" => "Quarantine flaky tests",
        "monitor_type" => "flakiness_rate",
        "trigger_config" => %{"threshold" => 5, "window_type" => "last_days", "window" => "30d"},
        "trigger_actions" => [%{"type" => "change_state", "state" => "muted"}]
      }

      assert {:ok, %Alert{} = automation} = Automations.create_alert(attrs)
      assert automation.name == "Quarantine flaky tests"
      assert automation.enabled == true
    end

    test "returns a changeset error for invalid attrs" do
      assert {:error, %Ecto.Changeset{}} = Automations.create_alert(%{})
    end
  end

  describe "update_alert/2" do
    test "updates the given automation" do
      automation = AutomationsFixtures.automation_alert_fixture()
      assert {:ok, updated} = Automations.update_alert(automation, %{"enabled" => false})
      refute updated.enabled
    end
  end

  describe "delete_alert/1" do
    test "deletes the automation" do
      automation = AutomationsFixtures.automation_alert_fixture()
      assert {:ok, _} = Automations.delete_alert(automation)
      assert {:error, :not_found} = Automations.get_alert(automation.id)
    end
  end

  describe "alert events" do
    test "create_alert_event and list_active_alert_events roundtrip" do
      alert = AutomationsFixtures.automation_alert_fixture()
      test_case_id = Ecto.UUID.generate()

      assert :ok =
               Automations.create_alert_event(%{
                 alert_id: alert.id,
                 test_case_id: test_case_id,
                 status: "triggered",
                 triggered_at: NaiveDateTime.utc_now()
               })

      events = Automations.list_active_alert_events(alert.id)
      assert Enum.any?(events, &(&1.test_case_id == test_case_id))
    end

    test "a recovered event is no longer listed as active" do
      alert = AutomationsFixtures.automation_alert_fixture()
      test_case_id = Ecto.UUID.generate()
      now = NaiveDateTime.utc_now()

      :ok =
        Automations.create_alert_event(%{
          alert_id: alert.id,
          test_case_id: test_case_id,
          status: "triggered",
          triggered_at: now
        })

      :ok =
        Automations.create_alert_event(%{
          alert_id: alert.id,
          test_case_id: test_case_id,
          status: "recovered",
          triggered_at: now,
          recovered_at: now
        })

      events = Automations.list_active_alert_events(alert.id)
      refute Enum.any?(events, &(&1.test_case_id == test_case_id))
    end
  end

  describe "dispatch_test_case_event/2" do
    defp test_updated_alert(project, opts \\ []) do
      AutomationsFixtures.automation_alert_fixture(
        Keyword.merge(
          [
            project: project,
            monitor_type: "test_updated",
            trigger_config: %{"events" => ["marked_flaky"]},
            trigger_actions: [%{"type" => "change_state", "state" => "muted"}]
          ],
          opts
        )
      )
    end

    test "runs trigger actions for an alert subscribed to :marked_flaky" do
      project = ProjectsFixtures.project_fixture()
      test_case = %{id: Ecto.UUID.generate(), project_id: project.id}
      alert = test_updated_alert(project)

      expected_entity = %{type: :test_case, id: test_case.id}

      expect(ActionExecutor, :execute_actions, fn actions, ^alert, ^expected_entity ->
        assert actions == alert.trigger_actions
        :ok
      end)

      assert :ok = Automations.dispatch_test_case_event(:marked_flaky, test_case)

      events = Automations.list_active_alert_events(alert.id)
      assert Enum.any?(events, &(&1.test_case_id == test_case.id))
    end

    test "skips disabled alerts" do
      project = ProjectsFixtures.project_fixture()
      test_case = %{id: Ecto.UUID.generate(), project_id: project.id}
      test_updated_alert(project, enabled: false)

      reject(&ActionExecutor.execute_actions/3)

      assert :ok = Automations.dispatch_test_case_event(:marked_flaky, test_case)
    end

    test "skips alerts from other projects" do
      project = ProjectsFixtures.project_fixture()
      other_project = ProjectsFixtures.project_fixture()
      test_case = %{id: Ecto.UUID.generate(), project_id: project.id}
      test_updated_alert(other_project)

      reject(&ActionExecutor.execute_actions/3)

      assert :ok = Automations.dispatch_test_case_event(:marked_flaky, test_case)
    end

    test "skips alerts whose monitor_type isn't test_updated" do
      project = ProjectsFixtures.project_fixture()
      test_case = %{id: Ecto.UUID.generate(), project_id: project.id}

      AutomationsFixtures.automation_alert_fixture(
        project: project,
        monitor_type: "flaky_run_count",
        trigger_config: %{"threshold" => 3, "window_type" => "last_days", "window" => "30d"}
      )

      reject(&ActionExecutor.execute_actions/3)

      assert :ok = Automations.dispatch_test_case_event(:marked_flaky, test_case)
    end

    test "skips alerts not subscribed to the firing event" do
      project = ProjectsFixtures.project_fixture()
      test_case = %{id: Ecto.UUID.generate(), project_id: project.id}
      # Subscribed only to unmarked_flaky.
      test_updated_alert(project, trigger_config: %{"events" => ["unmarked_flaky"]})

      reject(&ActionExecutor.execute_actions/3)

      assert :ok = Automations.dispatch_test_case_event(:marked_flaky, test_case)
    end

    test ":unmarked_flaky fires an alert subscribed to unmarked_flaky" do
      project = ProjectsFixtures.project_fixture()
      test_case = %{id: Ecto.UUID.generate(), project_id: project.id}
      alert = test_updated_alert(project, trigger_config: %{"events" => ["unmarked_flaky"]})

      expect(ActionExecutor, :execute_actions, fn _actions, ^alert, _entity -> :ok end)

      assert :ok = Automations.dispatch_test_case_event(:unmarked_flaky, test_case)
    end

    test "an alert can subscribe to multiple events and fires on each" do
      project = ProjectsFixtures.project_fixture()
      test_case = %{id: Ecto.UUID.generate(), project_id: project.id}

      alert =
        test_updated_alert(project,
          trigger_config: %{
            "events" => ["marked_flaky", "state_changed_to_muted", "state_changed_to_enabled"]
          }
        )

      # Three matching firings: :marked_flaky, :muted, :unmuted.
      expect(ActionExecutor, :execute_actions, 3, fn _actions, ^alert, _entity -> :ok end)

      assert :ok = Automations.dispatch_test_case_event(:marked_flaky, test_case)
      assert :ok = Automations.dispatch_test_case_event(:muted, test_case)
      # :unmuted maps to state_changed_to_enabled (subscribed).
      assert :ok = Automations.dispatch_test_case_event(:unmuted, test_case)
      # :skipped is NOT in the subscription, so this is a no-op.
      assert :ok = Automations.dispatch_test_case_event(:skipped, test_case)
    end

    test ":unmuted and :unskipped both map to state_changed_to_enabled" do
      project = ProjectsFixtures.project_fixture()
      test_case = %{id: Ecto.UUID.generate(), project_id: project.id}
      alert = test_updated_alert(project, trigger_config: %{"events" => ["state_changed_to_enabled"]})

      expect(ActionExecutor, :execute_actions, 2, fn _actions, ^alert, _entity -> :ok end)

      assert :ok = Automations.dispatch_test_case_event(:unmuted, test_case)
      assert :ok = Automations.dispatch_test_case_event(:unskipped, test_case)
    end

    test "does not record an alert event when actions fail" do
      project = ProjectsFixtures.project_fixture()
      test_case = %{id: Ecto.UUID.generate(), project_id: project.id}
      alert = test_updated_alert(project)

      expect(ActionExecutor, :execute_actions, fn _actions, _alert, _entity ->
        {:error, :boom}
      end)

      assert :ok = Automations.dispatch_test_case_event(:marked_flaky, test_case)
      assert Automations.list_active_alert_events(alert.id) == []
    end

    test "depth guard prevents test_case dispatcher from looping into the issue_link dispatcher" do
      project = ProjectsFixtures.project_fixture()
      test_case = %{id: Ecto.UUID.generate(), project_id: project.id}
      _test_alert = test_updated_alert(project)
      _issue_alert = github_issue_alert(project)
      issue_link = %{project_id: project.id}

      counter = :counters.new(1, [])

      stub(ActionExecutor, :execute_actions, fn _actions, _alert, _entity ->
        :counters.add(counter, 1, 1)
        # Cross-dispatcher recursion: a test_updated action that closes a
        # GH issue would re-enter via the issue_link dispatcher. Without a
        # shared counter this would loop forever.
        Automations.dispatch_issue_link_event(:closed, issue_link, test_case)
        :ok
      end)

      assert :ok = Automations.dispatch_test_case_event(:marked_flaky, test_case)

      assert :counters.get(counter, 1) == 10
    end

    test "depth guard caps recursion when an action re-fires the same event" do
      project = ProjectsFixtures.project_fixture()
      test_case = %{id: Ecto.UUID.generate(), project_id: project.id}
      _alert = test_updated_alert(project)

      # Simulate an automation whose action re-emits the same test case
      # event (the canonical cycle: a `state_changed_to_muted` alert that
      # mutes the test on fire). Without a guard this would loop forever.
      counter = :counters.new(1, [])

      stub(ActionExecutor, :execute_actions, fn _actions, _alert, _entity ->
        :counters.add(counter, 1, 1)
        Automations.dispatch_test_case_event(:marked_flaky, test_case)
        :ok
      end)

      assert :ok = Automations.dispatch_test_case_event(:marked_flaky, test_case)

      # The dispatcher allows depths 0..9 to run, so we expect exactly 10
      # executor invocations before the guard trips on the 11th level.
      assert :counters.get(counter, 1) == 10
    end
  end

  describe "issue links" do
    defp issue_link_attrs(project, alert, overrides \\ %{}) do
      Map.merge(
        %{
          project_id: project.id,
          alert_id: alert.id,
          test_case_id: Ecto.UUID.generate(),
          github_repository_full_handle: "tuist/tuist",
          github_issue_number: 42,
          opened_at: DateTime.truncate(DateTime.utc_now(), :second)
        },
        overrides
      )
    end

    test "create_issue_link inserts a row" do
      project = ProjectsFixtures.project_fixture()
      alert = AutomationsFixtures.automation_alert_fixture(project: project)

      assert {:ok, %IssueLink{} = link} =
               Automations.create_issue_link(issue_link_attrs(project, alert))

      assert link.state == "open"
      assert link.github_issue_number == 42
    end

    test "create_issue_link rejects a second open link for the same (alert, test_case)" do
      project = ProjectsFixtures.project_fixture()
      alert = AutomationsFixtures.automation_alert_fixture(project: project)
      test_case_id = Ecto.UUID.generate()

      assert {:ok, _} =
               Automations.create_issue_link(issue_link_attrs(project, alert, %{test_case_id: test_case_id}))

      assert {:error, _changeset} =
               Automations.create_issue_link(
                 issue_link_attrs(project, alert, %{
                   test_case_id: test_case_id,
                   github_issue_number: 43
                 })
               )
    end

    test "get_open_issue_link returns the matching open row, nil otherwise" do
      project = ProjectsFixtures.project_fixture()
      alert = AutomationsFixtures.automation_alert_fixture(project: project)
      test_case_id = Ecto.UUID.generate()

      assert Automations.get_open_issue_link(alert.id, test_case_id) == nil

      {:ok, link} =
        Automations.create_issue_link(issue_link_attrs(project, alert, %{test_case_id: test_case_id}))

      assert %IssueLink{id: id} = Automations.get_open_issue_link(alert.id, test_case_id)
      assert id == link.id
    end

    test "resolve_issue_link flips state and stamps resolved_at" do
      project = ProjectsFixtures.project_fixture()
      alert = AutomationsFixtures.automation_alert_fixture(project: project)
      {:ok, link} = Automations.create_issue_link(issue_link_attrs(project, alert))

      assert {:ok, resolved} = Automations.resolve_issue_link(link)
      assert resolved.state == "resolved"
      assert %DateTime{} = resolved.resolved_at
    end

    test "get_open_issue_link returns nil after the link is resolved" do
      project = ProjectsFixtures.project_fixture()
      alert = AutomationsFixtures.automation_alert_fixture(project: project)
      test_case_id = Ecto.UUID.generate()

      {:ok, link} =
        Automations.create_issue_link(issue_link_attrs(project, alert, %{test_case_id: test_case_id}))

      {:ok, _resolved} = Automations.resolve_issue_link(link)

      assert Automations.get_open_issue_link(alert.id, test_case_id) == nil
    end

    test "get_issue_link_by_github_coordinates looks up by (installation, repo, issue)" do
      user = TuistTestSupport.Fixtures.AccountsFixtures.user_fixture()

      installation =
        VCSFixtures.github_app_installation_fixture(
          account_id: user.account.id,
          installation_id: "12345"
        )

      project = ProjectsFixtures.project_fixture(account: user.account)
      alert = AutomationsFixtures.automation_alert_fixture(project: project)

      {:ok, link} =
        Automations.create_issue_link(
          issue_link_attrs(project, alert, %{
            github_app_installation_id: installation.id,
            github_repository_full_handle: "tuist/tuist",
            github_issue_number: 99
          })
        )

      assert {:ok, found} =
               Automations.get_issue_link_by_github_coordinates(
                 installation.id,
                 "tuist/tuist",
                 99
               )

      assert found.id == link.id

      assert {:error, :not_found} =
               Automations.get_issue_link_by_github_coordinates(
                 installation.id,
                 "tuist/tuist",
                 999
               )
    end
  end

  describe "dispatch_issue_link_event/3" do
    defp github_issue_alert(project, opts \\ []) do
      AutomationsFixtures.automation_alert_fixture(
        Keyword.merge(
          [
            project: project,
            monitor_type: "github_issue",
            trigger_config: %{"events" => ["closed"]},
            trigger_actions: [%{"type" => "remove_label", "label" => "flaky"}]
          ],
          opts
        )
      )
    end

    test "runs trigger actions for an alert subscribed to closed" do
      project = ProjectsFixtures.project_fixture()
      test_case = %{id: Ecto.UUID.generate(), project_id: project.id}
      alert = github_issue_alert(project)
      issue_link = %{project_id: project.id}

      expected_entity = %{type: :test_case, id: test_case.id}

      expect(ActionExecutor, :execute_actions, fn actions, ^alert, ^expected_entity ->
        assert actions == alert.trigger_actions
        :ok
      end)

      assert :ok = Automations.dispatch_issue_link_event(:closed, issue_link, test_case)

      events = Automations.list_active_alert_events(alert.id)
      assert Enum.any?(events, &(&1.test_case_id == test_case.id))
    end

    test "skips disabled alerts" do
      project = ProjectsFixtures.project_fixture()
      test_case = %{id: Ecto.UUID.generate(), project_id: project.id}
      github_issue_alert(project, enabled: false)
      issue_link = %{project_id: project.id}

      reject(&ActionExecutor.execute_actions/3)

      assert :ok = Automations.dispatch_issue_link_event(:closed, issue_link, test_case)
    end

    test "skips alerts from other projects" do
      project = ProjectsFixtures.project_fixture()
      other_project = ProjectsFixtures.project_fixture()
      test_case = %{id: Ecto.UUID.generate(), project_id: project.id}
      github_issue_alert(other_project)
      issue_link = %{project_id: project.id}

      reject(&ActionExecutor.execute_actions/3)

      assert :ok = Automations.dispatch_issue_link_event(:closed, issue_link, test_case)
    end

    test "skips alerts whose monitor_type isn't github_issue" do
      project = ProjectsFixtures.project_fixture()
      test_case = %{id: Ecto.UUID.generate(), project_id: project.id}

      AutomationsFixtures.automation_alert_fixture(
        project: project,
        monitor_type: "flaky_run_count",
        trigger_config: %{"threshold" => 3, "window_type" => "last_days", "window" => "30d"}
      )

      issue_link = %{project_id: project.id}
      reject(&ActionExecutor.execute_actions/3)

      assert :ok = Automations.dispatch_issue_link_event(:closed, issue_link, test_case)
    end
  end
end
