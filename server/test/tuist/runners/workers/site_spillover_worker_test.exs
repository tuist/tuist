defmodule Tuist.Runners.Workers.SiteSpilloverWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Repo
  alias Tuist.Runners.Workers.SiteSpilloverWorker
  alias Tuist.Runners.WorkflowJob
  alias Tuist.Runners.WorkflowJobs

  setup do
    prefix = Tuist.Environment.runners_macos_pool_name_prefix()

    stub(Tuist.Environment, :runners_site_pools, fn ->
      %{
        "#{prefix}-ber1-26-6" => %{site: "ber1", platform: :macos},
        "tuist-runner-pool-ber1" => %{site: "ber1", platform: :macos}
      }
    end)

    %{prefix: prefix, account: account_fixture()}
  end

  defp queue(account, workflow_job_id, fleet, seconds_ago) do
    :ok =
      WorkflowJobs.upsert_queued(%{
        workflow_job_id: workflow_job_id,
        account_id: account.id,
        fleet_name: fleet,
        platform: "macos",
        vcpus: 6,
        memory_gb: 14,
        repository: "tuist/tuist",
        requested_dispatch_label: "tuist-macos",
        enqueued_at: DateTime.add(DateTime.utc_now(), -seconds_ago, :second)
      })
  end

  defp fleet(workflow_job_id), do: Repo.get!(WorkflowJob, workflow_job_id).fleet_name

  test "moves a site job no site runner claimed in time to the rented pool", %{prefix: prefix, account: account} do
    queue(account, 920_001, "#{prefix}-ber1-26-6", 300)

    assert :ok = perform_job(SiteSpilloverWorker, %{})

    assert fleet(920_001) == "#{prefix}-26-6"
  end

  test "leaves a site job that is still within its wait", %{prefix: prefix, account: account} do
    queue(account, 920_002, "#{prefix}-ber1-26-6", 30)

    assert :ok = perform_job(SiteSpilloverWorker, %{})

    assert fleet(920_002) == "#{prefix}-ber1-26-6"
  end

  test "leaves an explicit site pool, which has no rented twin", %{account: account} do
    queue(account, 920_003, "tuist-runner-pool-ber1", 300)

    assert :ok = perform_job(SiteSpilloverWorker, %{})

    assert fleet(920_003) == "tuist-runner-pool-ber1"
  end
end
