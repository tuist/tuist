defmodule TuistTestSupport.Fixtures.RunnersFixtures do
  @moduledoc false

  alias Tuist.Repo
  alias Tuist.Runners
  alias TuistTestSupport.Fixtures.AccountsFixtures

  def runner_configuration_fixture(opts \\ []) do
    account_id =
      Keyword.get_lazy(opts, :account_id, fn ->
        user = AccountsFixtures.user_fixture(preload: [:account])
        user.account.id
      end)

    {:ok, config} =
      Runners.create_runner_configuration(%{
        account_id: account_id,
        enabled: Keyword.get(opts, :enabled, true),
        provisioning_mode: Keyword.get(opts, :provisioning_mode, :managed),
        default_tart_image: Keyword.get(opts, :default_tart_image, "ghcr.io/tuist/runner-macos-15:latest"),
        max_concurrent_jobs: Keyword.get(opts, :max_concurrent_jobs, 5),
        label_prefix: Keyword.get(opts, :label_prefix, "tuist-runner"),
        orchard_controller_url: Keyword.get(opts, :orchard_controller_url),
        orchard_service_account_name: Keyword.get(opts, :orchard_service_account_name)
      })

    Repo.preload(config, Keyword.get(opts, :preload, []))
  end

  def runner_job_fixture(opts \\ []) do
    config =
      Keyword.get_lazy(opts, :runner_configuration, fn ->
        config_opts =
          if Keyword.has_key?(opts, :account_id) do
            [account_id: Keyword.get(opts, :account_id)]
          else
            []
          end

        runner_configuration_fixture(config_opts)
      end)

    {:ok, job} =
      Runners.create_runner_job(%{
        runner_configuration_id: config.id,
        account_id: config.account_id,
        github_workflow_job_id: Keyword.get(opts, :github_workflow_job_id, TuistTestSupport.Utilities.unique_integer()),
        github_run_id: Keyword.get(opts, :github_run_id, TuistTestSupport.Utilities.unique_integer()),
        github_repository_full_name: Keyword.get(opts, :github_repository_full_name, "tuist/tuist"),
        labels: Keyword.get(opts, :labels, ["tuist-runner"]),
        queued_at: Keyword.get(opts, :queued_at, DateTime.utc_now())
      })

    Repo.preload(job, Keyword.get(opts, :preload, []))
  end
end
