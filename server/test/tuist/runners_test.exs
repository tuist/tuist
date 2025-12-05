defmodule Tuist.RunnersTest do
  use TuistTestSupport.Cases.DataCase

  alias Tuist.Runners
  alias TuistTestSupport.Fixtures.RunnersFixtures

  describe "get_available_hosts/0" do
    test "returns only hosts with available capacity" do
      # Host with capacity, no jobs
      host1 = RunnersFixtures.runner_host_fixture(capacity: 2)

      # Host with capacity, one job
      host2 = RunnersFixtures.runner_host_fixture(capacity: 2)
      RunnersFixtures.runner_job_fixture(host: host2, status: :running)

      # Host at capacity
      host3 = RunnersFixtures.runner_host_fixture(capacity: 1)
      RunnersFixtures.runner_job_fixture(host: host3, status: :running)

      # Host over capacity (edge case)
      host4 = RunnersFixtures.runner_host_fixture(capacity: 1)
      RunnersFixtures.runner_job_fixture(host: host4, status: :running)
      RunnersFixtures.runner_job_fixture(host: host4, status: :spawning)

      # Offline host with capacity
      _host5 = RunnersFixtures.runner_host_fixture(capacity: 2, status: :offline)

      available = Runners.get_available_hosts()
      available_ids = Enum.map(available, & &1.id)

      assert host1.id in available_ids
      assert host2.id in available_ids
      refute host3.id in available_ids
      refute host4.id in available_ids
    end

    test "counts only active jobs (pending, spawning, running, cleanup)" do
      host = RunnersFixtures.runner_host_fixture(capacity: 3)

      # Active jobs
      RunnersFixtures.runner_job_fixture(host: host, status: :pending)
      RunnersFixtures.runner_job_fixture(host: host, status: :spawning)

      # Completed jobs (shouldn't count)
      RunnersFixtures.runner_job_fixture(host: host, status: :completed)
      RunnersFixtures.runner_job_fixture(host: host, status: :failed)
      RunnersFixtures.runner_job_fixture(host: host, status: :cancelled)

      available = Runners.get_available_hosts()
      assert Enum.any?(available, &(&1.id == host.id))
    end

    test "returns empty list when no hosts have capacity" do
      host = RunnersFixtures.runner_host_fixture(capacity: 1)
      RunnersFixtures.runner_job_fixture(host: host, status: :running)

      assert Runners.get_available_hosts() == []
    end
  end

  describe "get_best_available_host/0" do
    test "returns the host with the least active jobs" do
      host1 = RunnersFixtures.runner_host_fixture(capacity: 5)
      host2 = RunnersFixtures.runner_host_fixture(capacity: 5)
      host3 = RunnersFixtures.runner_host_fixture(capacity: 5)

      # host1: 3 jobs
      RunnersFixtures.runner_job_fixture(host: host1, status: :running)
      RunnersFixtures.runner_job_fixture(host: host1, status: :running)
      RunnersFixtures.runner_job_fixture(host: host1, status: :spawning)

      # host2: 1 job (should be selected)
      RunnersFixtures.runner_job_fixture(host: host2, status: :running)

      # host3: 2 jobs
      RunnersFixtures.runner_job_fixture(host: host3, status: :running)
      RunnersFixtures.runner_job_fixture(host: host3, status: :pending)

      best = Runners.get_best_available_host()
      assert best.id == host2.id
    end

    test "returns host with no jobs when available" do
      host1 = RunnersFixtures.runner_host_fixture(capacity: 2)
      host2 = RunnersFixtures.runner_host_fixture(capacity: 2)

      RunnersFixtures.runner_job_fixture(host: host2, status: :running)

      best = Runners.get_best_available_host()
      assert best.id == host1.id
    end

    test "returns nil when no hosts have capacity" do
      host = RunnersFixtures.runner_host_fixture(capacity: 1)
      RunnersFixtures.runner_job_fixture(host: host, status: :running)

      assert Runners.get_best_available_host() == nil
    end

    test "returns nil when no hosts exist" do
      assert Runners.get_best_available_host() == nil
    end
  end

  describe "get_active_job_count/1" do
    test "counts only active jobs for the host" do
      host = RunnersFixtures.runner_host_fixture()
      other_host = RunnersFixtures.runner_host_fixture()

      # Active jobs on the host
      RunnersFixtures.runner_job_fixture(host: host, status: :pending)
      RunnersFixtures.runner_job_fixture(host: host, status: :spawning)
      RunnersFixtures.runner_job_fixture(host: host, status: :running)
      RunnersFixtures.runner_job_fixture(host: host, status: :cleanup)

      # Inactive jobs on the host
      RunnersFixtures.runner_job_fixture(host: host, status: :completed)
      RunnersFixtures.runner_job_fixture(host: host, status: :failed)

      # Jobs on other host
      RunnersFixtures.runner_job_fixture(host: other_host, status: :running)

      assert Runners.get_active_job_count(host.id) == 4
    end

    test "returns 0 when host has no jobs" do
      host = RunnersFixtures.runner_host_fixture()
      assert Runners.get_active_job_count(host.id) == 0
    end
  end

  describe "host_has_capacity?/1" do
    test "returns true when host has available capacity" do
      host = RunnersFixtures.runner_host_fixture(capacity: 3)
      RunnersFixtures.runner_job_fixture(host: host, status: :running)

      assert Runners.host_has_capacity?(host)
    end

    test "returns false when host is at capacity" do
      host = RunnersFixtures.runner_host_fixture(capacity: 2)
      RunnersFixtures.runner_job_fixture(host: host, status: :running)
      RunnersFixtures.runner_job_fixture(host: host, status: :spawning)

      refute Runners.host_has_capacity?(host)
    end

    test "returns true when host has no jobs" do
      host = RunnersFixtures.runner_host_fixture(capacity: 1)
      assert Runners.host_has_capacity?(host)
    end
  end

  describe "get_organization_active_job_count/1" do
    test "counts only active jobs for the organization" do
      org1 = RunnersFixtures.runner_organization_fixture()
      org2 = RunnersFixtures.runner_organization_fixture()

      # Active jobs for org1
      RunnersFixtures.runner_job_fixture(organization: org1, status: :pending)
      RunnersFixtures.runner_job_fixture(organization: org1, status: :running)
      RunnersFixtures.runner_job_fixture(organization: org1, status: :cleanup)

      # Inactive jobs for org1
      RunnersFixtures.runner_job_fixture(organization: org1, status: :completed)
      RunnersFixtures.runner_job_fixture(organization: org1, status: :failed)

      # Jobs for org2
      RunnersFixtures.runner_job_fixture(organization: org2, status: :running)

      assert Runners.get_organization_active_job_count(org1.id) == 3
    end

    test "returns 0 when organization has no jobs" do
      org = RunnersFixtures.runner_organization_fixture()
      assert Runners.get_organization_active_job_count(org.id) == 0
    end
  end

  describe "organization_has_capacity?/1" do
    test "returns true when max_concurrent_jobs is nil (unlimited)" do
      org = RunnersFixtures.runner_organization_fixture(max_concurrent_jobs: nil)
      RunnersFixtures.runner_job_fixture(organization: org, status: :running)
      RunnersFixtures.runner_job_fixture(organization: org, status: :running)

      assert Runners.organization_has_capacity?(org)
    end

    test "returns true when under the limit" do
      org = RunnersFixtures.runner_organization_fixture(max_concurrent_jobs: 3)
      RunnersFixtures.runner_job_fixture(organization: org, status: :running)

      assert Runners.organization_has_capacity?(org)
    end

    test "returns false when at the limit" do
      org = RunnersFixtures.runner_organization_fixture(max_concurrent_jobs: 2)
      RunnersFixtures.runner_job_fixture(organization: org, status: :running)
      RunnersFixtures.runner_job_fixture(organization: org, status: :spawning)

      refute Runners.organization_has_capacity?(org)
    end

    test "returns false when over the limit" do
      org = RunnersFixtures.runner_organization_fixture(max_concurrent_jobs: 1)
      RunnersFixtures.runner_job_fixture(organization: org, status: :running)
      RunnersFixtures.runner_job_fixture(organization: org, status: :spawning)

      refute Runners.organization_has_capacity?(org)
    end
  end
end
