defmodule Tuist.Runners.Workers.SiteSpilloverWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Repo
  alias Tuist.Runners.Sites
  alias Tuist.Runners.Workers.SiteSpilloverWorker
  alias Tuist.Runners.WorkflowJob
  alias Tuist.Runners.WorkflowJobs

  setup :verify_on_exit!

  setup do
    prefix = Tuist.Environment.runners_macos_pool_name_prefix()

    stub(Tuist.Environment, :runners_site_pools, fn ->
      %{
        "#{prefix}-ber1-26-6" => %{site: "ber1", platform: :macos},
        "#{prefix}-ber1-27-0" => %{site: "ber1", platform: :macos},
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

  test "keeps site jobs on a site that is up, however long they queue", %{prefix: prefix, account: account} do
    stub(Sites, :status, fn _site_pool -> :up end)
    queue(account, 920_001, "#{prefix}-ber1-27-0", 300)

    assert :ok = perform_job(SiteSpilloverWorker, %{})

    assert fleet(920_001) == "#{prefix}-ber1-27-0"
  end

  test "moves every queued job of a site pool that is down to the rented pool", %{prefix: prefix, account: account} do
    down_pool = "#{prefix}-ber1-26-6"

    stub(Sites, :status, fn
      ^down_pool -> {:down, :no_capacity}
      _site_pool -> :up
    end)

    queue(account, 920_002, "#{prefix}-ber1-26-6", 300)
    queue(account, 920_003, "#{prefix}-ber1-26-6", 0)
    queue(account, 920_004, "#{prefix}-ber1-27-0", 300)

    assert :ok = perform_job(SiteSpilloverWorker, %{})

    assert fleet(920_002) == "#{prefix}-26-6"
    assert fleet(920_003) == "#{prefix}-26-6"
    assert fleet(920_004) == "#{prefix}-ber1-27-0"
  end

  test "moves the jobs of a stalled site pool", %{prefix: prefix, account: account} do
    stub(Sites, :status, fn _site_pool -> {:down, :stalled} end)
    queue(account, 920_005, "#{prefix}-ber1-27-0", 700)

    assert :ok = perform_job(SiteSpilloverWorker, %{})

    assert fleet(920_005) == "#{prefix}-27-0"
  end

  test "reads no site state for pools with nothing queued", %{prefix: prefix, account: account} do
    queued_pool = "#{prefix}-ber1-26-6"
    expect(Sites, :status, 1, fn ^queued_pool -> :up end)
    queue(account, 920_006, "#{prefix}-ber1-26-6", 30)

    assert :ok = perform_job(SiteSpilloverWorker, %{})
  end

  test "leaves the jobs of a site pool that is down when the env rents no macOS fleet", %{
    prefix: prefix,
    account: account
  } do
    stub(Tuist.Environment, :runners_rented_macos_fleet?, fn -> false end)
    reject(&Sites.status/1)
    queue(account, 920_008, "#{prefix}-ber1-26-6", 3_600)

    assert :ok = perform_job(SiteSpilloverWorker, %{})

    assert fleet(920_008) == "#{prefix}-ber1-26-6"
  end

  test "leaves an explicit site pool, which has no rented twin", %{account: account} do
    reject(&Sites.status/1)
    queue(account, 920_007, "tuist-runner-pool-ber1", 300)

    assert :ok = perform_job(SiteSpilloverWorker, %{})

    assert fleet(920_007) == "tuist-runner-pool-ber1"
  end
end
