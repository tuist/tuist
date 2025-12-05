defmodule TuistTestSupport.Fixtures.RunnersFixtures do
  @moduledoc false

  alias Tuist.Accounts.Account
  alias Tuist.Runners

  def runner_host_fixture(opts \\ []) do
    attrs = %{
      name: Keyword.get(opts, :name, "test-host-#{TuistTestSupport.Utilities.unique_integer()}"),
      ip: Keyword.get(opts, :ip, "192.168.1.#{:rand.uniform(254)}"),
      ssh_port: Keyword.get(opts, :ssh_port, 22),
      capacity: Keyword.get(opts, :capacity, 4),
      status: Keyword.get(opts, :status, :online),
      chip_type: Keyword.get(opts, :chip_type, :m2),
      ram_gb: Keyword.get(opts, :ram_gb, 16),
      storage_gb: Keyword.get(opts, :storage_gb, 256),
      last_heartbeat_at: Keyword.get(opts, :last_heartbeat_at, DateTime.utc_now())
    }

    {:ok, host} = Runners.create_runner_host(attrs)
    host
  end

  def runner_organization_fixture(opts \\ []) do
    account =
      cond do
        Keyword.has_key?(opts, :account) ->
          Keyword.get(opts, :account)

        Keyword.has_key?(opts, :account_id) ->
          Tuist.Repo.get!(Account, Keyword.get(opts, :account_id))

        true ->
          organization = TuistTestSupport.Fixtures.AccountsFixtures.organization_fixture()

          Tuist.Repo.get_by!(Account,
            organization_id: organization.id
          )
      end

    {:ok, org} =
      Runners.create_runner_organization(%{
        account_id: account.id,
        enabled: Keyword.get(opts, :enabled, true),
        label_prefix: Keyword.get(opts, :label_prefix, "tuist-runners"),
        allowed_labels: Keyword.get(opts, :allowed_labels, []),
        max_concurrent_jobs: Keyword.get(opts, :max_concurrent_jobs, 10),
        github_app_installation_id: Keyword.get(opts, :github_app_installation_id, :rand.uniform(1_000_000))
      })

    org
  end

  def runner_job_fixture(opts \\ []) do
    runner_org =
      cond do
        Keyword.has_key?(opts, :organization) ->
          Keyword.get(opts, :organization)

        Keyword.has_key?(opts, :organization_id) ->
          Runners.get_runner_organization(Keyword.get(opts, :organization_id))

        true ->
          runner_organization_fixture()
      end

    host =
      cond do
        Keyword.has_key?(opts, :host) ->
          Keyword.get(opts, :host)

        Keyword.has_key?(opts, :host_id) ->
          Runners.get_runner_host(Keyword.get(opts, :host_id))

        true ->
          nil
      end

    unique_id = TuistTestSupport.Utilities.unique_integer()
    target_status = Keyword.get(opts, :status, :pending)

    attrs = %{
      github_job_id: Keyword.get(opts, :github_job_id, unique_id),
      run_id: Keyword.get(opts, :run_id, unique_id + 1000),
      org: Keyword.get(opts, :org, "test-org"),
      repo: Keyword.get(opts, :repo, "test-org/test-repo"),
      labels: Keyword.get(opts, :labels, ["tuist-runners"]),
      status: :pending,
      organization_id: runner_org.id,
      host_id: host && host.id,
      vm_name: Keyword.get(opts, :vm_name),
      started_at: Keyword.get(opts, :started_at),
      completed_at: Keyword.get(opts, :completed_at),
      github_workflow_url: Keyword.get(opts, :github_workflow_url),
      github_runner_name: Keyword.get(opts, :github_runner_name),
      error_message: Keyword.get(opts, :error_message)
    }

    {:ok, job} = Runners.create_runner_job(attrs)
    transition_job_to_status(job, target_status)
  end

  defp transition_job_to_status(job, :pending), do: job

  defp transition_job_to_status(job, :spawning) do
    {:ok, job} = Runners.update_runner_job(job, %{status: :spawning})
    job
  end

  defp transition_job_to_status(job, :running) do
    job = transition_job_to_status(job, :spawning)
    {:ok, job} = Runners.update_runner_job(job, %{status: :running})
    job
  end

  defp transition_job_to_status(job, :cleanup) do
    job = transition_job_to_status(job, :running)
    {:ok, job} = Runners.update_runner_job(job, %{status: :cleanup})
    job
  end

  defp transition_job_to_status(job, :completed) do
    job = transition_job_to_status(job, :cleanup)
    {:ok, job} = Runners.update_runner_job(job, %{status: :completed})
    job
  end

  defp transition_job_to_status(job, :failed) do
    job = transition_job_to_status(job, :spawning)
    {:ok, job} = Runners.update_runner_job(job, %{status: :failed})
    job
  end

  defp transition_job_to_status(job, :cancelled) do
    {:ok, job} = Runners.update_runner_job(job, %{status: :cancelled})
    job
  end
end
