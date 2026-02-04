defmodule Tuist.Alerts.Workers.FlakyThresholdCheckWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Alerts.Workers.FlakyTestAlertWorker
  alias Tuist.Alerts.Workers.FlakyThresholdCheckWorker
  alias Tuist.Tests
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  setup do
    user = AccountsFixtures.user_fixture()
    project = ProjectsFixtures.project_fixture(account_id: user.account.id)
    %{user: user, project: project}
  end

  describe "perform/1" do
    test "returns ok when test_case_ids is empty", %{project: project} do
      result =
        FlakyThresholdCheckWorker.perform(%Oban.Job{
          args: %{"project_id" => project.id, "test_case_ids" => []}
        })

      assert result == :ok
    end

    test "returns ok when project is not found" do
      result =
        FlakyThresholdCheckWorker.perform(%Oban.Job{
          args: %{"project_id" => -1, "test_case_ids" => [Ecto.UUID.generate()]}
        })

      assert result == :ok
    end

    test "does not mark test case as flaky when below threshold", %{project: project} do
      {:ok, project} =
        Tuist.Projects.update_project(project, %{auto_mark_flaky_threshold: 3})

      test_case = RunsFixtures.test_case_fixture(project_id: project.id, is_flaky: false)

      stub(Tests, :get_flaky_runs_groups_counts_for_test_cases, fn _ids ->
        %{test_case.id => 2}
      end)

      stub(Tests, :get_test_case_by_id, fn _id -> {:ok, test_case} end)
      reject(&Tests.update_test_case/3)

      result =
        FlakyThresholdCheckWorker.perform(%Oban.Job{
          args: %{"project_id" => project.id, "test_case_ids" => [test_case.id]}
        })

      assert result == :ok
    end

    test "marks test case as flaky when at threshold", %{project: project} do
      {:ok, project} =
        Tuist.Projects.update_project(project, %{
          auto_mark_flaky_threshold: 3,
          auto_quarantine_flaky_tests: false
        })

      test_case = RunsFixtures.test_case_fixture(project_id: project.id, is_flaky: false)

      stub(Tests, :get_flaky_runs_groups_counts_for_test_cases, fn _ids ->
        %{test_case.id => 3}
      end)

      stub(Tests, :get_test_case_by_id, fn _id -> {:ok, test_case} end)

      expect(Tests, :update_test_case, fn id, attrs ->
        assert id == test_case.id
        assert attrs == %{is_flaky: true}
        {:ok, Map.merge(test_case, attrs)}
      end)

      result =
        FlakyThresholdCheckWorker.perform(%Oban.Job{
          args: %{"project_id" => project.id, "test_case_ids" => [test_case.id]}
        })

      assert result == :ok

      assert_enqueued(
        worker: FlakyTestAlertWorker,
        args: %{
          test_case_id: test_case.id,
          project_id: project.id,
          auto_quarantined: false,
          flaky_runs_count: 3
        }
      )
    end

    test "marks test case as flaky and quarantined when auto_quarantine is enabled", %{project: project} do
      {:ok, project} =
        Tuist.Projects.update_project(project, %{
          auto_mark_flaky_threshold: 2,
          auto_quarantine_flaky_tests: true
        })

      test_case = RunsFixtures.test_case_fixture(project_id: project.id, is_flaky: false)

      stub(Tests, :get_flaky_runs_groups_counts_for_test_cases, fn _ids ->
        %{test_case.id => 5}
      end)

      stub(Tests, :get_test_case_by_id, fn _id -> {:ok, test_case} end)

      expect(Tests, :update_test_case, fn id, attrs ->
        assert id == test_case.id
        assert attrs == %{is_flaky: true, is_quarantined: true}
        {:ok, Map.merge(test_case, attrs)}
      end)

      result =
        FlakyThresholdCheckWorker.perform(%Oban.Job{
          args: %{"project_id" => project.id, "test_case_ids" => [test_case.id]}
        })

      assert result == :ok

      assert_enqueued(
        worker: FlakyTestAlertWorker,
        args: %{
          test_case_id: test_case.id,
          project_id: project.id,
          auto_quarantined: true,
          flaky_runs_count: 5
        }
      )
    end

    test "does not mark already flaky test cases", %{project: project} do
      {:ok, project} =
        Tuist.Projects.update_project(project, %{auto_mark_flaky_threshold: 1})

      test_case = RunsFixtures.test_case_fixture(project_id: project.id, is_flaky: true)

      stub(Tests, :get_flaky_runs_groups_counts_for_test_cases, fn _ids ->
        %{test_case.id => 5}
      end)

      stub(Tests, :get_test_case_by_id, fn _id -> {:ok, test_case} end)
      reject(&Tests.update_test_case/3)

      result =
        FlakyThresholdCheckWorker.perform(%Oban.Job{
          args: %{"project_id" => project.id, "test_case_ids" => [test_case.id]}
        })

      assert result == :ok
      refute_enqueued(worker: FlakyTestAlertWorker)
    end

    test "processes multiple test cases in batch", %{project: project} do
      {:ok, project} =
        Tuist.Projects.update_project(project, %{
          auto_mark_flaky_threshold: 2,
          auto_quarantine_flaky_tests: false
        })

      test_case_1 = RunsFixtures.test_case_fixture(project_id: project.id, is_flaky: false, name: "test_1")
      test_case_2 = RunsFixtures.test_case_fixture(project_id: project.id, is_flaky: false, name: "test_2")
      test_case_3 = RunsFixtures.test_case_fixture(project_id: project.id, is_flaky: true, name: "test_3")

      id_1 = test_case_1.id
      id_2 = test_case_2.id
      id_3 = test_case_3.id

      stub(Tests, :get_flaky_runs_groups_counts_for_test_cases, fn _ids ->
        %{id_1 => 3, id_2 => 1, id_3 => 5}
      end)

      stub(Tests, :get_test_case_by_id, fn id ->
        case id do
          ^id_1 -> {:ok, test_case_1}
          ^id_2 -> {:ok, test_case_2}
          ^id_3 -> {:ok, test_case_3}
        end
      end)

      expect(Tests, :update_test_case, fn id, attrs ->
        assert id == test_case_1.id
        assert attrs == %{is_flaky: true}
        {:ok, Map.merge(test_case_1, attrs)}
      end)

      result =
        FlakyThresholdCheckWorker.perform(%Oban.Job{
          args: %{
            "project_id" => project.id,
            "test_case_ids" => [test_case_1.id, test_case_2.id, test_case_3.id]
          }
        })

      assert result == :ok

      assert_enqueued(
        worker: FlakyTestAlertWorker,
        args: %{
          test_case_id: test_case_1.id,
          project_id: project.id,
          auto_quarantined: false,
          flaky_runs_count: 3
        }
      )
    end
  end
end
