defmodule Tuist.Slack.AlertsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Slack.Alerts
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistTestSupport.Fixtures.SlackFixtures

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

      alert =
        SlackFixtures.slack_alert_fixture(
          project: project,
          category: :build_run_duration,
          metric: :average,
          threshold_percentage: 20.0,
          sample_size: 10
        )

      alert = Repo.preload(alert, project: :account)

      # When
      result = Alerts.evaluate(alert)

      # Then
      assert result == :ok
    end

    test "returns {:triggered, result} when threshold exceeded" do
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

      alert =
        SlackFixtures.slack_alert_fixture(
          project: project,
          category: :build_run_duration,
          metric: :average,
          threshold_percentage: 20.0,
          sample_size: 5
        )

      alert = Repo.preload(alert, project: :account)

      # When
      result = Alerts.evaluate(alert)

      # Then
      assert {:triggered, data} = result
      assert data.current == 1200.0
      assert data.previous == 1000.0
      assert data.change_pct == 20.0
    end

    test "returns :ok when no current data" do
      # Given
      project = ProjectsFixtures.project_fixture()

      alert =
        SlackFixtures.slack_alert_fixture(
          project: project,
          category: :build_run_duration,
          sample_size: 5
        )

      alert = Repo.preload(alert, project: :account)

      # When
      result = Alerts.evaluate(alert)

      # Then
      assert result == :ok
    end
  end

  describe "evaluate/1 for test_run_duration" do
    test "returns {:triggered, result} when threshold exceeded" do
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

      alert =
        SlackFixtures.slack_alert_fixture(
          project: project,
          category: :test_run_duration,
          metric: :average,
          threshold_percentage: 15.0,
          sample_size: 5
        )

      alert = Repo.preload(alert, project: :account)

      # When
      result = Alerts.evaluate(alert)

      # Then
      assert {:triggered, data} = result
      assert data.current == 2300.0
      assert data.previous == 2000.0
      assert data.change_pct == 15.0
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

      alert =
        SlackFixtures.slack_alert_fixture(
          project: project,
          category: :test_run_duration,
          metric: :average,
          threshold_percentage: 20.0,
          sample_size: 5
        )

      alert = Repo.preload(alert, project: :account)

      # When
      result = Alerts.evaluate(alert)

      # Then
      assert result == :ok
    end
  end

  describe "evaluate/1 for cache_hit_rate" do
    test "returns {:triggered, result} when cache hit rate decreased" do
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

      alert =
        SlackFixtures.slack_alert_fixture(
          project: project,
          category: :cache_hit_rate,
          metric: :average,
          threshold_percentage: 10.0,
          sample_size: 5
        )

      alert = Repo.preload(alert, project: :account)

      # When
      result = Alerts.evaluate(alert)

      # Then
      # Decrease of 12.5% ((0.8 - 0.7) / 0.8 * 100)
      assert {:triggered, data} = result
      assert data.current == 0.7
      assert data.previous == 0.8
      assert data.change_pct == 12.5
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

      alert =
        SlackFixtures.slack_alert_fixture(
          project: project,
          category: :cache_hit_rate,
          metric: :average,
          threshold_percentage: 10.0,
          sample_size: 5
        )

      alert = Repo.preload(alert, project: :account)

      # When
      result = Alerts.evaluate(alert)

      # Then
      assert result == :ok
    end
  end

  describe "build_alert_blocks/2" do
    test "returns valid Slack blocks for build_run_duration alert" do
      # Given
      project = ProjectsFixtures.project_fixture()

      alert =
        SlackFixtures.slack_alert_fixture(
          project: project,
          category: :build_run_duration,
          metric: :p90
        )

      alert = Repo.preload(alert, project: :account)

      result = %{
        current: 1200,
        previous: 1000,
        change_pct: 20.0
      }

      stub(Tuist.Environment, :app_url, fn -> "https://cloud.tuist.dev" end)

      # When
      blocks = Alerts.build_alert_blocks(alert, result)

      # Then
      assert is_list(blocks)
      assert length(blocks) == 5

      # Check header block
      [header | _] = blocks
      assert header.type == "header"
      assert String.contains?(header.text.text, "Build Time")
    end

    test "returns valid Slack blocks for test_run_duration alert" do
      # Given
      project = ProjectsFixtures.project_fixture()

      alert =
        SlackFixtures.slack_alert_fixture(
          project: project,
          category: :test_run_duration,
          metric: :p99
        )

      alert = Repo.preload(alert, project: :account)

      result = %{
        current: 5000,
        previous: 4000,
        change_pct: 25.0
      }

      stub(Tuist.Environment, :app_url, fn -> "https://cloud.tuist.dev" end)

      # When
      blocks = Alerts.build_alert_blocks(alert, result)

      # Then
      assert is_list(blocks)
      [header | _] = blocks
      assert String.contains?(header.text.text, "Test Time")
    end

    test "returns valid Slack blocks for cache_hit_rate alert" do
      # Given
      project = ProjectsFixtures.project_fixture()

      alert =
        SlackFixtures.slack_alert_fixture(
          project: project,
          category: :cache_hit_rate,
          metric: :average
        )

      alert = Repo.preload(alert, project: :account)

      result = %{
        current: 0.7,
        previous: 0.85,
        change_pct: 17.6
      }

      stub(Tuist.Environment, :app_url, fn -> "https://cloud.tuist.dev" end)

      # When
      blocks = Alerts.build_alert_blocks(alert, result)

      # Then
      assert is_list(blocks)
      [header | _] = blocks
      assert String.contains?(header.text.text, "Cache Hit Rate")
    end

    test "includes project link in footer" do
      # Given
      project = ProjectsFixtures.project_fixture()

      alert =
        SlackFixtures.slack_alert_fixture(
          project: project,
          category: :build_run_duration
        )

      alert = Repo.preload(alert, project: :account)

      result = %{current: 1200, previous: 1000, change_pct: 20.0}

      stub(Tuist.Environment, :app_url, fn -> "https://cloud.tuist.dev" end)

      # When
      blocks = Alerts.build_alert_blocks(alert, result)

      # Then
      footer = List.last(blocks)
      assert footer.type == "context"
      [element] = footer.elements
      assert String.contains?(element.text, "View project")
      assert String.contains?(element.text, project.account.name)
      assert String.contains?(element.text, project.name)
    end
  end
end
