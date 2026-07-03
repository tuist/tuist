defmodule Tuist.Tests.Workers.BroadcastTestCreatedWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Tests.Test
  alias Tuist.Tests.Workers.BroadcastTestCreatedWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  describe "perform/1" do
    test "broadcasts :test_created on the project topic so dashboards refresh" do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      {:ok, test_run} =
        RunsFixtures.test_fixture(project_id: project.id, account_id: user.account.id)

      Tuist.PubSub.subscribe("#{user.account.name}/#{project.name}")

      assert :ok =
               perform_job(BroadcastTestCreatedWorker, %{
                 test_run_id: test_run.id,
                 project_id: project.id
               })

      assert_receive {:test_created, %Test{id: broadcasted_id}}
      assert broadcasted_id == test_run.id
    end

    test "is a no-op when the test run no longer exists" do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      Tuist.PubSub.subscribe("#{user.account.name}/#{project.name}")

      assert :ok =
               perform_job(BroadcastTestCreatedWorker, %{
                 test_run_id: UUIDv7.generate(),
                 project_id: project.id
               })

      refute_receive {:test_created, _}
    end
  end
end
