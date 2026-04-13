defmodule Tuist.Runners.Workers.ProvisionRunnerWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.GitHub.Client
  alias Tuist.Runners
  alias Tuist.Runners.Workers.ProvisionRunnerWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.RunnersFixtures
  alias TuistTestSupport.Fixtures.VCSFixtures

  setup :verify_on_exit!

  setup do
    user = AccountsFixtures.user_fixture(preload: [:account])
    installation = VCSFixtures.github_app_installation_fixture(account_id: user.account.id)

    config =
      RunnersFixtures.runner_configuration_fixture(account_id: user.account.id)

    job = RunnersFixtures.runner_job_fixture(runner_configuration: config)

    stub(Tuist.Environment, :get, fn
      [:orchard, :controller_url] -> "https://orchard.test.com"
      [:orchard, :service_account_name] -> "test-sa"
      [:orchard, :service_account_token] -> "test-token"
      _keys -> nil
    end)

    %{
      user: user,
      installation: installation,
      config: config,
      job: job
    }
  end

  test "provisions a runner successfully", %{job: job, installation: installation} do
    expect(Client, :generate_jit_config, fn params ->
      assert params.installation_id == installation.installation_id
      assert params.repository_full_name == "tuist/tuist"

      {:ok, %{runner_id: 123, encoded_jit_config: "base64-jit-config"}}
    end)

    expect(Tuist.Runners.OrchardClient, :create_vm, fn _config, attrs ->
      assert attrs.image == "ghcr.io/tuist/runner-macos-15:latest"
      assert String.starts_with?(attrs.name, "tuist-runner-")
      assert attrs.startup_script =~ "jitconfig"

      {:ok, %{"name" => attrs.name, "status" => "creating"}}
    end)

    assert :ok == ProvisionRunnerWorker.perform(%Oban.Job{args: %{"runner_job_id" => job.id}})

    {:ok, updated_job} = Runners.get_runner_job(job.id)
    assert updated_job.status == :provisioning
    assert updated_job.orchard_vm_name
    assert updated_job.tart_image == "ghcr.io/tuist/runner-macos-15:latest"
  end

  test "marks job as failed when JIT config generation fails", %{job: job} do
    expect(Client, :generate_jit_config, fn _params ->
      {:error, "GitHub API error"}
    end)

    assert {:error, "GitHub API error"} ==
             ProvisionRunnerWorker.perform(%Oban.Job{args: %{"runner_job_id" => job.id}})

    {:ok, updated_job} = Runners.get_runner_job(job.id)
    assert updated_job.status == :failed
    assert updated_job.error_message =~ "Provisioning failed"
  end

  test "snoozes when concurrency limit reached", %{config: config, job: job} do
    Runners.update_runner_configuration(config, %{max_concurrent_jobs: 1})

    assert {:snooze, 15} ==
             ProvisionRunnerWorker.perform(%Oban.Job{args: %{"runner_job_id" => job.id}})
  end
end
