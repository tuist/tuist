defmodule Tuist.Alerts.Workers.FlakyThresholdCheckWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Alerts.Workers.FlakyThresholdCheckWorker
  alias Tuist.Projects
  alias Tuist.Runs
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  setup do
    user = %{account: account} = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    %{user: user, project: project, account: account}
  end

  describe "perform/1" do
    test "marks test case as flaky when threshold is reached", %{project: project} do
      # Given
      {:ok, project} =
        Projects.update_project(project, %{
          auto_mark_flaky_tests: true,
          auto_mark_flaky_threshold: 3,
          auto_quarantine_flaky_tests: false
        })

      test_case = RunsFixtures.test_case_fixture(project_id: project.id, is_flaky: false)

      stub(Runs, :get_test_case_by_id, fn _id -> {:ok, test_case} end)
      stub(Runs, :get_flaky_runs_groups_count_for_test_case, fn _id -> 3 end)

      expect(Runs, :update_test_case, fn id, %{is_flaky: true} ->
        assert id == test_case.id
        {:ok, %{test_case | is_flaky: true}}
      end)

      expect(Oban, :insert!, fn changeset ->
        assert changeset.changes.args[:test_case_id] == test_case.id
        assert changeset.changes.args[:project_id] == project.id
        %Oban.Job{}
      end)

      # When
      result =
        FlakyThresholdCheckWorker.perform(%Oban.Job{
          args: %{"test_case_id" => test_case.id, "project_id" => project.id}
        })

      # Then
      assert result == :ok
    end

    test "auto-quarantines when enabled and threshold is reached", %{project: project} do
      # Given
      {:ok, project} =
        Projects.update_project(project, %{
          auto_mark_flaky_tests: true,
          auto_mark_flaky_threshold: 1,
          auto_quarantine_flaky_tests: true
        })

      test_case = RunsFixtures.test_case_fixture(project_id: project.id, is_flaky: false)

      stub(Runs, :get_test_case_by_id, fn _id -> {:ok, test_case} end)
      stub(Runs, :get_flaky_runs_groups_count_for_test_case, fn _id -> 2 end)

      expect(Runs, :update_test_case, fn id, %{is_flaky: true} ->
        assert id == test_case.id
        {:ok, %{test_case | is_flaky: true}}
      end)

      expect(Runs, :update_test_case, fn id, %{is_quarantined: true} ->
        assert id == test_case.id
        {:ok, %{test_case | is_quarantined: true}}
      end)

      expect(Oban, :insert!, fn _changeset -> %Oban.Job{} end)

      # When
      result =
        FlakyThresholdCheckWorker.perform(%Oban.Job{
          args: %{"test_case_id" => test_case.id, "project_id" => project.id}
        })

      # Then
      assert result == :ok
    end

    test "skips if test case is already flaky", %{project: project} do
      # Given
      {:ok, project} =
        Projects.update_project(project, %{
          auto_mark_flaky_tests: true,
          auto_mark_flaky_threshold: 1
        })

      test_case = RunsFixtures.test_case_fixture(project_id: project.id, is_flaky: true)

      stub(Runs, :get_test_case_by_id, fn _id -> {:ok, test_case} end)

      reject(&Runs.get_flaky_runs_groups_count_for_test_case/1)
      reject(&Runs.update_test_case/2)
      reject(&Oban.insert!/1)

      # When
      result =
        FlakyThresholdCheckWorker.perform(%Oban.Job{
          args: %{"test_case_id" => test_case.id, "project_id" => project.id}
        })

      # Then
      assert result == :ok
    end

    test "skips if auto_mark_flaky_tests is disabled", %{project: project} do
      # Given
      {:ok, project} =
        Projects.update_project(project, %{
          auto_mark_flaky_tests: false,
          auto_mark_flaky_threshold: 1
        })

      test_case = RunsFixtures.test_case_fixture(project_id: project.id, is_flaky: false)

      stub(Runs, :get_test_case_by_id, fn _id -> {:ok, test_case} end)

      reject(&Runs.get_flaky_runs_groups_count_for_test_case/1)
      reject(&Runs.update_test_case/2)
      reject(&Oban.insert!/1)

      # When
      result =
        FlakyThresholdCheckWorker.perform(%Oban.Job{
          args: %{"test_case_id" => test_case.id, "project_id" => project.id}
        })

      # Then
      assert result == :ok
    end

    test "skips if flaky runs count is below threshold", %{project: project} do
      # Given
      {:ok, project} =
        Projects.update_project(project, %{
          auto_mark_flaky_tests: true,
          auto_mark_flaky_threshold: 5
        })

      test_case = RunsFixtures.test_case_fixture(project_id: project.id, is_flaky: false)

      stub(Runs, :get_test_case_by_id, fn _id -> {:ok, test_case} end)
      stub(Runs, :get_flaky_runs_groups_count_for_test_case, fn _id -> 3 end)

      reject(&Runs.update_test_case/2)
      reject(&Oban.insert!/1)

      # When
      result =
        FlakyThresholdCheckWorker.perform(%Oban.Job{
          args: %{"test_case_id" => test_case.id, "project_id" => project.id}
        })

      # Then
      assert result == :ok
    end

    test "returns :ok when test case is not found", %{project: project} do
      # Given
      test_case_id = Ecto.UUID.generate()

      stub(Runs, :get_test_case_by_id, fn _id -> {:error, :not_found} end)

      reject(&Runs.get_flaky_runs_groups_count_for_test_case/1)
      reject(&Runs.update_test_case/2)
      reject(&Oban.insert!/1)

      # When
      result =
        FlakyThresholdCheckWorker.perform(%Oban.Job{
          args: %{"test_case_id" => test_case_id, "project_id" => project.id}
        })

      # Then
      assert result == :ok
    end

    test "returns :ok when project is not found" do
      # Given
      test_case_id = Ecto.UUID.generate()
      project_id = Ecto.UUID.generate()

      test_case = %Tuist.Runs.TestCase{
        id: test_case_id,
        project_id: project_id,
        name: "test_example",
        is_flaky: false
      }

      stub(Runs, :get_test_case_by_id, fn _id -> {:ok, test_case} end)
      stub(Projects, :get_project_by_id, fn _id -> nil end)

      reject(&Runs.get_flaky_runs_groups_count_for_test_case/1)
      reject(&Runs.update_test_case/2)
      reject(&Oban.insert!/1)

      # When
      result =
        FlakyThresholdCheckWorker.perform(%Oban.Job{
          args: %{"test_case_id" => test_case_id, "project_id" => project_id}
        })

      # Then
      assert result == :ok
    end

    test "marks flaky when count equals threshold exactly", %{project: project} do
      # Given
      {:ok, project} =
        Projects.update_project(project, %{
          auto_mark_flaky_tests: true,
          auto_mark_flaky_threshold: 2,
          auto_quarantine_flaky_tests: false
        })

      test_case = RunsFixtures.test_case_fixture(project_id: project.id, is_flaky: false)

      stub(Runs, :get_test_case_by_id, fn _id -> {:ok, test_case} end)
      stub(Runs, :get_flaky_runs_groups_count_for_test_case, fn _id -> 2 end)

      expect(Runs, :update_test_case, fn _id, %{is_flaky: true} ->
        {:ok, %{test_case | is_flaky: true}}
      end)

      expect(Oban, :insert!, fn _changeset -> %Oban.Job{} end)

      # When
      result =
        FlakyThresholdCheckWorker.perform(%Oban.Job{
          args: %{"test_case_id" => test_case.id, "project_id" => project.id}
        })

      # Then
      assert result == :ok
    end

    test "does not mark flaky when count is one below threshold", %{project: project} do
      # Given
      {:ok, project} =
        Projects.update_project(project, %{
          auto_mark_flaky_tests: true,
          auto_mark_flaky_threshold: 3,
          auto_quarantine_flaky_tests: false
        })

      test_case = RunsFixtures.test_case_fixture(project_id: project.id, is_flaky: false)

      stub(Runs, :get_test_case_by_id, fn _id -> {:ok, test_case} end)
      stub(Runs, :get_flaky_runs_groups_count_for_test_case, fn _id -> 2 end)

      reject(&Runs.update_test_case/2)
      reject(&Oban.insert!/1)

      # When
      result =
        FlakyThresholdCheckWorker.perform(%Oban.Job{
          args: %{"test_case_id" => test_case.id, "project_id" => project.id}
        })

      # Then
      assert result == :ok
    end
  end
end
