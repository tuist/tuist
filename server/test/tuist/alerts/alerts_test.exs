defmodule Tuist.AlertsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Alerts
  alias Tuist.Alerts.Alert
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.AlertsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  describe "evaluate/1 for build_run_duration" do
    test "returns :ok when current is not worse than previous" do
      # Given
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      # Create 10 "current" builds with duration 1000
      for i <- 1..10 do
        {:ok, _} =
          RunsFixtures.build_fixture(
            project_id: project.id,
            user_id: user.account.id,
            duration: 1000,
            inserted_at: DateTime.add(DateTime.utc_now(), -i, :minute)
          )
      end

      # Create 10 "previous" builds with duration 1000 (same as current)
      for i <- 11..20 do
        {:ok, _} =
          RunsFixtures.build_fixture(
            project_id: project.id,
            user_id: user.account.id,
            duration: 1000,
            inserted_at: DateTime.add(DateTime.utc_now(), -i, :minute)
          )
      end

      alert_rule =
        AlertsFixtures.alert_rule_fixture(
          project: project,
          category: :build_run_duration,
          metric: :average,
          threshold_percentage: 20.0,
          sample_size: 10
        )

      alert_rule = Repo.preload(alert_rule, project: :account)

      # When
      result = Alerts.evaluate(alert_rule)

      # Then
      assert result == :ok
    end

    test "returns {:triggered, alert} when threshold exceeded" do
      # Given
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      # Create 5 "current" builds with duration 1200 (20% higher)
      for i <- 1..5 do
        {:ok, _} =
          RunsFixtures.build_fixture(
            project_id: project.id,
            user_id: user.account.id,
            duration: 1200,
            inserted_at: DateTime.add(DateTime.utc_now(), -i, :minute)
          )
      end

      # Create 5 "previous" builds with duration 1000
      for i <- 6..10 do
        {:ok, _} =
          RunsFixtures.build_fixture(
            project_id: project.id,
            user_id: user.account.id,
            duration: 1000,
            inserted_at: DateTime.add(DateTime.utc_now(), -i, :minute)
          )
      end

      alert_rule =
        AlertsFixtures.alert_rule_fixture(
          project: project,
          category: :build_run_duration,
          metric: :average,
          threshold_percentage: 20.0,
          sample_size: 5
        )

      alert_rule = Repo.preload(alert_rule, project: :account)

      # When
      result = Alerts.evaluate(alert_rule)

      # Then
      assert {:triggered, result} = result
      assert result.current == 1200.0
      assert result.previous == 1000.0
      assert result.change_pct == 20.0
    end

    test "returns :ok when no current data" do
      # Given
      project = ProjectsFixtures.project_fixture()

      alert_rule =
        AlertsFixtures.alert_rule_fixture(
          project: project,
          category: :build_run_duration,
          sample_size: 5
        )

      alert_rule = Repo.preload(alert_rule, project: :account)

      # When
      result = Alerts.evaluate(alert_rule)

      # Then
      assert result == :ok
    end
  end

  describe "evaluate/1 for test_run_duration" do
    test "returns {:triggered, alert} when threshold exceeded" do
      # Given
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      # Create 5 "current" tests with duration 2300 (15% higher)
      for i <- 1..5 do
        {:ok, _} =
          RunsFixtures.test_fixture(
            project_id: project.id,
            account_id: user.account.id,
            duration: 2300,
            ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -i * 60, :second)
          )
      end

      # Create 5 "previous" tests with duration 2000
      for i <- 6..10 do
        {:ok, _} =
          RunsFixtures.test_fixture(
            project_id: project.id,
            account_id: user.account.id,
            duration: 2000,
            ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -i * 60, :second)
          )
      end

      alert_rule =
        AlertsFixtures.alert_rule_fixture(
          project: project,
          category: :test_run_duration,
          metric: :average,
          threshold_percentage: 15.0,
          sample_size: 5
        )

      alert_rule = Repo.preload(alert_rule, project: :account)

      # When
      result = Alerts.evaluate(alert_rule)

      # Then
      assert {:triggered, result} = result
      assert result.current == 2300.0
      assert result.previous == 2000.0
      assert result.change_pct == 15.0
    end

    test "returns :ok when no regression" do
      # Given
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      # Create 5 "current" tests with same duration as previous
      for i <- 1..10 do
        {:ok, _} =
          RunsFixtures.test_fixture(
            project_id: project.id,
            account_id: user.account.id,
            duration: 1000,
            ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -i * 60, :second)
          )
      end

      alert_rule =
        AlertsFixtures.alert_rule_fixture(
          project: project,
          category: :test_run_duration,
          metric: :average,
          threshold_percentage: 20.0,
          sample_size: 5
        )

      alert_rule = Repo.preload(alert_rule, project: :account)

      # When
      result = Alerts.evaluate(alert_rule)

      # Then
      assert result == :ok
    end
  end

  describe "evaluate/1 for cache_hit_rate" do
    test "returns {:triggered, alert} when cache hit rate decreased" do
      # Given
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      # Create 5 "current" builds with 70% cache hit rate
      for i <- 1..5 do
        {:ok, _} =
          RunsFixtures.build_fixture(
            project_id: project.id,
            user_id: user.account.id,
            duration: 1000,
            cacheable_tasks_count: 100,
            cacheable_task_local_hits_count: 50,
            cacheable_task_remote_hits_count: 20,
            inserted_at: DateTime.add(DateTime.utc_now(), -i, :minute)
          )
      end

      # Create 5 "previous" builds with 80% cache hit rate
      for i <- 6..10 do
        {:ok, _} =
          RunsFixtures.build_fixture(
            project_id: project.id,
            user_id: user.account.id,
            duration: 1000,
            cacheable_tasks_count: 100,
            cacheable_task_local_hits_count: 60,
            cacheable_task_remote_hits_count: 20,
            inserted_at: DateTime.add(DateTime.utc_now(), -i, :minute)
          )
      end

      alert_rule =
        AlertsFixtures.alert_rule_fixture(
          project: project,
          category: :cache_hit_rate,
          metric: :average,
          threshold_percentage: 10.0,
          sample_size: 5
        )

      alert_rule = Repo.preload(alert_rule, project: :account)

      # When
      result = Alerts.evaluate(alert_rule)

      # Then
      # Decrease of 12.5% ((0.8 - 0.7) / 0.8 * 100)
      assert {:triggered, result} = result
      assert result.current == 0.7
      assert result.previous == 0.8
      assert result.change_pct == 12.5
    end

    test "returns :ok when cache hit rate improved" do
      # Given
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      # Create 5 "current" builds with 90% cache hit rate (improved)
      for i <- 1..5 do
        {:ok, _} =
          RunsFixtures.build_fixture(
            project_id: project.id,
            user_id: user.account.id,
            duration: 1000,
            cacheable_tasks_count: 100,
            cacheable_task_local_hits_count: 70,
            cacheable_task_remote_hits_count: 20,
            inserted_at: DateTime.add(DateTime.utc_now(), -i, :minute)
          )
      end

      # Create 5 "previous" builds with 80% cache hit rate
      for i <- 6..10 do
        {:ok, _} =
          RunsFixtures.build_fixture(
            project_id: project.id,
            user_id: user.account.id,
            duration: 1000,
            cacheable_tasks_count: 100,
            cacheable_task_local_hits_count: 60,
            cacheable_task_remote_hits_count: 20,
            inserted_at: DateTime.add(DateTime.utc_now(), -i, :minute)
          )
      end

      alert_rule =
        AlertsFixtures.alert_rule_fixture(
          project: project,
          category: :cache_hit_rate,
          metric: :average,
          threshold_percentage: 10.0,
          sample_size: 5
        )

      alert_rule = Repo.preload(alert_rule, project: :account)

      # When
      result = Alerts.evaluate(alert_rule)

      # Then
      assert result == :ok
    end
  end

  describe "list_project_alert_rules/1" do
    test "returns alert rules for a project" do
      # Given
      project = ProjectsFixtures.project_fixture()
      alert_rule1 = AlertsFixtures.alert_rule_fixture(project: project, category: :build_run_duration)
      alert_rule2 = AlertsFixtures.alert_rule_fixture(project: project, category: :test_run_duration)

      # When
      alert_rules = Alerts.list_project_alert_rules(project.id)

      # Then
      assert length(alert_rules) == 2
      alert_rule_ids = Enum.map(alert_rules, & &1.id)
      assert alert_rule1.id in alert_rule_ids
      assert alert_rule2.id in alert_rule_ids
    end

    test "returns empty list when project has no alert rules" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      alert_rules = Alerts.list_project_alert_rules(project.id)

      # Then
      assert alert_rules == []
    end
  end

  describe "get_alert_rule/1" do
    test "returns alert rule when it exists" do
      # Given
      alert_rule = AlertsFixtures.alert_rule_fixture()

      # When
      result = Alerts.get_alert_rule(alert_rule.id)

      # Then
      assert {:ok, fetched} = result
      assert fetched.id == alert_rule.id
    end

    test "returns error when alert rule does not exist" do
      # Given
      non_existent_id = Ecto.UUID.generate()

      # When
      result = Alerts.get_alert_rule(non_existent_id)

      # Then
      assert {:error, :not_found} = result
    end
  end

  describe "create_alert_rule/1" do
    test "creates an alert rule with valid attributes" do
      # Given
      project = ProjectsFixtures.project_fixture()

      attrs = %{
        project_id: project.id,
        category: :build_run_duration,
        metric: :p90,
        threshold_percentage: 20.0,
        sample_size: 100,
        slack_channel_id: "C123456",
        slack_channel_name: "test-channel"
      }

      # When
      result = Alerts.create_alert_rule(attrs)

      # Then
      assert {:ok, alert_rule} = result
      assert alert_rule.project_id == project.id
      assert alert_rule.category == :build_run_duration
      assert alert_rule.metric == :p90
      assert alert_rule.threshold_percentage == 20.0
      assert alert_rule.sample_size == 100
      assert alert_rule.slack_channel_id == "C123456"
      assert alert_rule.slack_channel_name == "test-channel"
      assert alert_rule.enabled == true
    end

    test "returns error with invalid attributes" do
      # When
      result = Alerts.create_alert_rule(%{})

      # Then
      assert {:error, changeset} = result
      assert changeset.valid? == false
    end
  end

  describe "update_alert_rule/2" do
    test "updates an alert rule" do
      # Given
      alert_rule = AlertsFixtures.alert_rule_fixture()

      # When
      result = Alerts.update_alert_rule(alert_rule, %{threshold_percentage: 30.0, metric: :p99})

      # Then
      assert {:ok, updated} = result
      assert updated.threshold_percentage == 30.0
      assert updated.metric == :p99
      assert updated.category == alert_rule.category
    end

    test "can disable an alert rule" do
      # Given
      alert_rule = AlertsFixtures.alert_rule_fixture(enabled: true)

      # When
      result = Alerts.update_alert_rule(alert_rule, %{enabled: false})

      # Then
      assert {:ok, updated} = result
      assert updated.enabled == false
    end
  end

  describe "delete_alert_rule/1" do
    test "deletes an alert rule" do
      # Given
      alert_rule = AlertsFixtures.alert_rule_fixture()

      # When
      result = Alerts.delete_alert_rule(alert_rule)

      # Then
      assert {:ok, _deleted} = result
      assert Alerts.get_alert_rule(alert_rule.id) == {:error, :not_found}
    end
  end

  describe "list_enabled_alert_rules/0" do
    test "returns only enabled alert rules with preloaded associations" do
      # Given
      project = ProjectsFixtures.project_fixture()
      enabled_rule = AlertsFixtures.alert_rule_fixture(project: project, enabled: true)
      _disabled_rule = AlertsFixtures.alert_rule_fixture(project: project, enabled: false)

      # When
      alert_rules = Alerts.list_enabled_alert_rules()

      # Then
      alert_rule_ids = Enum.map(alert_rules, & &1.id)
      assert enabled_rule.id in alert_rule_ids
    end

    test "preloads project and account" do
      # Given
      project = ProjectsFixtures.project_fixture()
      _alert_rule = AlertsFixtures.alert_rule_fixture(project: project, enabled: true)

      # When
      [fetched_rule] = Alerts.list_enabled_alert_rules()

      # Then
      assert fetched_rule.project
      assert fetched_rule.project.account
    end
  end

  describe "cooldown_elapsed?/1" do
    test "returns true when no alerts exist for the rule" do
      # Given
      alert_rule = AlertsFixtures.alert_rule_fixture()

      # When/Then
      assert Alerts.cooldown_elapsed?(alert_rule) == true
    end

    test "returns true when more than 24 hours have passed since last alert" do
      # Given
      alert_rule = AlertsFixtures.alert_rule_fixture()

      # Create an alert that was inserted 25 hours ago
      twenty_five_hours_ago =
        DateTime.utc_now()
        |> DateTime.add(-25, :hour)
        |> DateTime.truncate(:second)

      Repo.insert!(%Alert{
        alert_rule_id: alert_rule.id,
        current_value: 1200.0,
        previous_value: 1000.0,
        inserted_at: twenty_five_hours_ago,
        updated_at: twenty_five_hours_ago
      })

      # When/Then
      assert Alerts.cooldown_elapsed?(alert_rule) == true
    end

    test "returns false when less than 24 hours have passed since last alert" do
      # Given
      alert_rule = AlertsFixtures.alert_rule_fixture()

      # Create an alert that was inserted 1 hour ago
      one_hour_ago =
        DateTime.utc_now()
        |> DateTime.add(-1, :hour)
        |> DateTime.truncate(:second)

      Repo.insert!(%Alert{
        alert_rule_id: alert_rule.id,
        current_value: 1200.0,
        previous_value: 1000.0,
        inserted_at: one_hour_ago,
        updated_at: one_hour_ago
      })

      # When/Then
      assert Alerts.cooldown_elapsed?(alert_rule) == false
    end
  end

  describe "create_alert/1" do
    test "creates an alert with valid attributes" do
      # Given
      alert_rule = AlertsFixtures.alert_rule_fixture()

      attrs = %{
        alert_rule_id: alert_rule.id,
        current_value: 1200.0,
        previous_value: 1000.0
      }

      # When
      result = Alerts.create_alert(attrs)

      # Then
      assert {:ok, alert} = result
      assert alert.alert_rule_id == alert_rule.id
      assert alert.current_value == 1200.0
      assert alert.previous_value == 1000.0
    end
  end

  describe "get_latest_alert/1" do
    test "returns the most recent alert for a rule" do
      # Given
      alert_rule = AlertsFixtures.alert_rule_fixture()

      now = DateTime.truncate(DateTime.utc_now(), :second)
      one_hour_ago = DateTime.add(now, -1, :hour)

      # Create older alert with explicit timestamp
      _older_alert =
        Repo.insert!(%Alert{
          alert_rule_id: alert_rule.id,
          current_value: 1100.0,
          previous_value: 1000.0,
          inserted_at: one_hour_ago,
          updated_at: one_hour_ago
        })

      # Create newer alert with explicit timestamp
      newer_alert =
        Repo.insert!(%Alert{
          alert_rule_id: alert_rule.id,
          current_value: 1200.0,
          previous_value: 1000.0,
          inserted_at: now,
          updated_at: now
        })

      # When
      result = Alerts.get_latest_alert(alert_rule.id)

      # Then
      assert result.id == newer_alert.id
      assert result.current_value == 1200.0
    end

    test "returns nil when no alerts exist" do
      # Given
      alert_rule = AlertsFixtures.alert_rule_fixture()

      # When
      result = Alerts.get_latest_alert(alert_rule.id)

      # Then
      assert result == nil
    end
  end
end
