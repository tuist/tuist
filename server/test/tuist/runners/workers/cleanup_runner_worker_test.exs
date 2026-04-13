defmodule Tuist.Runners.Workers.CleanupRunnerWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Runners
  alias Tuist.Runners.OrchardClient
  alias Tuist.Runners.Workers.CleanupRunnerWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.RunnersFixtures

  setup :verify_on_exit!

  setup do
    user = AccountsFixtures.user_fixture(preload: [:account])
    config = RunnersFixtures.runner_configuration_fixture(account_id: user.account.id)
    job = RunnersFixtures.runner_job_fixture(runner_configuration: config)

    {:ok, job} =
      Runners.update_runner_job(job, %{
        status: :provisioning,
        orchard_vm_name: "tuist-runner-abc123"
      })

    {:ok, job} = Runners.update_runner_job(job, %{status: :completed, conclusion: "success"})

    stub(Tuist.Environment, :get, fn
      [:orchard, :controller_url] -> "https://orchard.test.com"
      [:orchard, :service_account_name] -> "test-sa"
      [:orchard, :service_account_token] -> "test-token"
      _keys -> nil
    end)

    %{config: config, job: job}
  end

  test "cleans up VM successfully", %{job: job} do
    expect(OrchardClient, :delete_vm, fn _config, vm_name ->
      assert vm_name == "tuist-runner-abc123"
      :ok
    end)

    assert :ok == CleanupRunnerWorker.perform(%Oban.Job{args: %{"runner_job_id" => job.id}})
  end

  test "handles already-deleted VM gracefully", %{job: job} do
    expect(OrchardClient, :delete_vm, fn _config, _vm_name ->
      :ok
    end)

    assert :ok == CleanupRunnerWorker.perform(%Oban.Job{args: %{"runner_job_id" => job.id}})
  end
end
