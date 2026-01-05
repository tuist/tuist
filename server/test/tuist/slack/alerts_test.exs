defmodule Tuist.Slack.AlertsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Slack.Alerts
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.SlackFixtures

  describe "evaluate/1 for build_run_duration" do
    test "returns :ok when current is not worse than previous" do
      # Given
      project = ProjectsFixtures.project_fixture()
      alert = SlackFixtures.slack_alert_fixture(project: project, category: :build_run_duration, metric: :p90, threshold_percentage: 20.0, sample_size: 10)
      alert = Repo.preload(alert, project: :account)

      stub(Tuist.Repo, :all, fn _query ->
        [1000, 1100, 1050, 1000, 1100, 1050, 1000, 1100, 1050, 1000]
      end)

      # When
      result = Alerts.evaluate(alert)

      # Then
      assert result == :ok
    end

    test "returns {:triggered, result} when threshold exceeded" do
      # Given
      project = ProjectsFixtures.project_fixture()
      alert = SlackFixtures.slack_alert_fixture(project: project, category: :build_run_duration, metric: :average, threshold_percentage: 20.0, sample_size: 5)
      alert = Repo.preload(alert, project: :account)

      # Mock: current average = 1200, previous average = 1000
      # First call returns current data, second returns previous
      call_count = :counters.new(1, [])

      stub(Tuist.Repo, :all, fn _query ->
        :counters.add(call_count, 1, 1)
        count = :counters.get(call_count, 1)

        if count == 1 do
          # Current: average = 1200
          [1200, 1200, 1200, 1200, 1200]
        else
          # Previous: average = 1000
          [1000, 1000, 1000, 1000, 1000]
        end
      end)

      # When
      result = Alerts.evaluate(alert)

      # Then
      assert {:triggered, data} = result
      assert data.current == 1200
      assert data.previous == 1000
      assert data.change_pct == 20.0
    end

    test "returns :ok when no current data" do
      # Given
      project = ProjectsFixtures.project_fixture()
      alert = SlackFixtures.slack_alert_fixture(project: project, category: :build_run_duration, sample_size: 5)
      alert = Repo.preload(alert, project: :account)

      stub(Tuist.Repo, :all, fn _query -> [] end)

      # When
      result = Alerts.evaluate(alert)

      # Then
      assert result == :ok
    end
  end

  describe "evaluate/1 for cache_hit_rate" do
    test "returns {:triggered, result} when cache hit rate decreased" do
      # Given
      project = ProjectsFixtures.project_fixture()
      alert = SlackFixtures.slack_alert_fixture(project: project, category: :cache_hit_rate, metric: :average, threshold_percentage: 10.0, sample_size: 5)
      alert = Repo.preload(alert, project: :account)

      call_count = :counters.new(1, [])

      stub(Tuist.Repo, :all, fn _query ->
        :counters.add(call_count, 1, 1)
        count = :counters.get(call_count, 1)

        if count == 1 do
          # Current: average = 0.7 (70%)
          [0.7, 0.7, 0.7, 0.7, 0.7]
        else
          # Previous: average = 0.8 (80%)
          [0.8, 0.8, 0.8, 0.8, 0.8]
        end
      end)

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
      project = ProjectsFixtures.project_fixture()
      alert = SlackFixtures.slack_alert_fixture(project: project, category: :cache_hit_rate, metric: :average, threshold_percentage: 10.0, sample_size: 5)
      alert = Repo.preload(alert, project: :account)

      call_count = :counters.new(1, [])

      stub(Tuist.Repo, :all, fn _query ->
        :counters.add(call_count, 1, 1)
        count = :counters.get(call_count, 1)

        if count == 1 do
          # Current: average = 0.9 (90%)
          [0.9, 0.9, 0.9, 0.9, 0.9]
        else
          # Previous: average = 0.8 (80%)
          [0.8, 0.8, 0.8, 0.8, 0.8]
        end
      end)

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
      alert = SlackFixtures.slack_alert_fixture(project: project, category: :build_run_duration, metric: :p90)
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
      alert = SlackFixtures.slack_alert_fixture(project: project, category: :test_run_duration, metric: :p99)
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
      alert = SlackFixtures.slack_alert_fixture(project: project, category: :cache_hit_rate, metric: :average)
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
      alert = SlackFixtures.slack_alert_fixture(project: project, category: :build_run_duration)
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
