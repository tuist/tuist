defmodule Tuist.Runners.ClaimsConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Tuist.Repo
  alias Tuist.Runners.Claim
  alias Tuist.Runners.Claims
  alias Tuist.Runners.ConcurrencyLimit
  alias Tuist.Runners.WorkflowJob
  alias Tuist.Runners.WorkflowJobs

  @db_task_ready_timeout 5_000
  @linux_resources %{platform: :linux, vcpus: 1, memory_gb: 1}

  setup do
    :ok = Sandbox.checkout(Repo, sandbox: false)
    :ok
  end

  test "simultaneous claims never exceed an account's platform limit" do
    with_accounts(1, fn [account] ->
      macos_resources = %{platform: :macos, vcpus: 6, memory_gb: 14}

      attempts =
        Enum.map(1..8, fn index ->
          fn ->
            attempt_until_decided(
              80_000 + index,
              account.id,
              "fleet-macos",
              "pod-#{index}",
              macos_resources
            )
          end
        end)

      results = run_concurrently(attempts)

      assert Enum.count(results, &match?({:ok, _claim}, &1)) == 2

      assert Enum.count(results, fn
               {:error, {:concurrency_limit_reached, _details}} -> true
               _other -> false
             end) == 6

      claims = Repo.all(from(claim in Claim, where: claim.account_id == ^account.id and claim.platform == :macos))

      assert Enum.sum(Enum.map(claims, & &1.vcpus)) == 12
      assert Enum.sum(Enum.map(claims, & &1.memory_gb)) == 28
    end)
  end

  test "a busy platform returns immediately while other admission scopes proceed" do
    with_accounts(2, fn [first_account, second_account] ->
      lock_task = hold_platform_lock(first_account.id, :linux)

      try do
        busy_attempt =
          start_db_task(fn ->
            Claims.attempt(81_001, first_account.id, "fleet-linux", "busy-pod", @linux_resources)
          end)

        assert {:error, :account_busy} = Task.await(busy_attempt, 1_000)

        assert {:ok, _} =
                 Claims.attempt(
                   81_002,
                   first_account.id,
                   "fleet-macos",
                   "macos-pod",
                   %{platform: :macos, vcpus: 6, memory_gb: 14}
                 )

        assert {:ok, _} =
                 Claims.attempt(81_003, second_account.id, "fleet-linux", "other-account-pod", @linux_resources)
      after
        send(lock_task.pid, :release)
        Task.await(lock_task)
      end
    end)
  end

  test "a unique-index wait does not hold the account platform lock" do
    with_accounts(2, fn [account, conflicting_account] ->
      conflicting_claim = hold_uncommitted_claim(conflicting_account.id, 81_100, "shared-pod")

      blocked_attempt =
        start_db_task(fn ->
          Claims.attempt(81_101, account.id, "fleet-linux", "shared-pod", @linux_resources)
        end)

      blocked_before_release = Task.yield(blocked_attempt, 100)

      independent_result =
        Claims.attempt(81_102, account.id, "fleet-linux", "independent-pod", @linux_resources)

      send(conflicting_claim.pid, :commit)
      assert {:ok, :committed} = Task.await(conflicting_claim)

      blocked_result =
        case blocked_before_release do
          nil -> Task.await(blocked_attempt)
          {:ok, result} -> result
        end

      assert blocked_before_release == nil
      assert {:ok, _claim} = independent_result
      assert {:error, :pod_in_use} = blocked_result
    end)
  end

  # The atomic-claim primitive moved off the primary key when claims were
  # re-keyed by Pod, onto a partial unique index on `workflow_job_id`. Two
  # Pods racing for the same queued job must still collapse to one claim,
  # or the job is dispatched twice and burns a second runner.
  test "simultaneous claims for the same job collapse to one" do
    with_accounts(1, fn [account] ->
      results =
        run_concurrently([
          fn -> attempt_until_decided(83_001, account.id, "fleet-a", "race-pod-1", @linux_resources) end,
          fn -> attempt_until_decided(83_001, account.id, "fleet-a", "race-pod-2", @linux_resources) end
        ])

      assert Enum.count(results, &match?({:ok, _claim}, &1)) == 1
      assert Enum.count(results, &match?({:error, :lost_race}, &1)) == 1
    end)
  end

  test "one pod cannot acquire concurrent claims across accounts" do
    with_accounts(2, fn [first_account, second_account] ->
      results =
        run_concurrently([
          fn -> Claims.attempt(82_001, first_account.id, "fleet-a", "shared-pod", @linux_resources) end,
          fn -> Claims.attempt(82_002, second_account.id, "fleet-a", "shared-pod", @linux_resources) end
        ])

      assert Enum.count(results, &match?({:ok, _claim}, &1)) == 1
      assert Enum.count(results, &match?({:error, :pod_in_use}, &1)) == 1
    end)
  end

  # The stale claim's own webhook can be processed while another runner's
  # webhook is handing that claim the displaced job. Working from a claim
  # read before the hand-over, it detached the job it remembered and left
  # the handed-over one attached to no claim, with no path back to the
  # queue until the orphan sweep.
  test "a stale claim's own webhook sees the job handed to it while it waited" do
    with_accounts(1, fn [account] ->
      for {id, fleet} <- [{86_101, "fleet-a"}, {86_102, "fleet-a"}, {86_103, "fleet-a"}] do
        :ok = WorkflowJobs.upsert_queued(lifecycle_attrs(account, id, fleet))
      end

      {:ok, _} = Claims.attempt(86_101, account.id, "fleet-a", "handover-pod-1", @linux_resources)
      {:ok, _} = Claims.attempt(86_102, account.id, "fleet-a", "handover-pod-2", @linux_resources)
      :ok = mark_running!(86_101, "handover-runner-1")
      :ok = mark_running!(86_102, "handover-runner-2")

      hand_over = hold_uncommitted(safely(fn -> Claims.record_execution("handover-runner-1", 86_102, account.id) end))

      own_webhook = start_db_task(safely(fn -> Claims.record_execution("handover-runner-2", 86_103, account.id) end))
      assert Task.yield(own_webhook, 200) == nil

      send(hand_over.pid, :commit)
      assert {:ok, {:mismatch, %{handed_to: "handover-pod-2"}}} = Task.await(hand_over)
      assert {:mismatch, %{workflow_job_id: 86_101, requeued: true}} = Task.await(own_webhook)

      assert Repo.get!(WorkflowJob, 86_101).status == "queued"
      assert Repo.get!(WorkflowJob, 86_102).pod_name == "handover-pod-1"
    end)
  end

  # GitHub routinely gives each of two runners the job the other was
  # minted for, and both `in_progress` webhooks land together. Each
  # transaction locks its own claim and then the other's, so unordered
  # locking deadlocks.
  test "simultaneous mutual displacements settle without deadlocking" do
    with_accounts(1, fn [account] ->
      pairs =
        Enum.map(1..10, fn index ->
          a = 86_200 + index * 2
          b = a + 1
          :ok = WorkflowJobs.upsert_queued(lifecycle_attrs(account, a, "fleet-a"))
          :ok = WorkflowJobs.upsert_queued(lifecycle_attrs(account, b, "fleet-a"))
          {:ok, _} = Claims.attempt(a, account.id, "fleet-a", "mutual-pod-#{index}-a", @linux_resources)
          {:ok, _} = Claims.attempt(b, account.id, "fleet-a", "mutual-pod-#{index}-b", @linux_resources)
          :ok = mark_running!(a, "mutual-runner-#{index}-a")
          :ok = mark_running!(b, "mutual-runner-#{index}-b")
          {index, a, b}
        end)

      results =
        pairs
        |> Enum.flat_map(fn {index, a, b} ->
          [
            safely(fn -> Claims.record_execution("mutual-runner-#{index}-a", b, account.id) end),
            safely(fn -> Claims.record_execution("mutual-runner-#{index}-b", a, account.id) end)
          ]
        end)
        |> run_concurrently()

      assert Enum.all?(results, &(match?({:mismatch, _}, &1) or &1 == :matched))

      for {index, a, b} <- pairs do
        assert Repo.get!(WorkflowJob, a).pod_name == "mutual-pod-#{index}-b"
        assert Repo.get!(WorkflowJob, b).pod_name == "mutual-pod-#{index}-a"
        assert Repo.get!(WorkflowJob, a).status == "running"
        assert Repo.get!(WorkflowJob, b).status == "running"
      end
    end)
  end

  # A raise inside a linked task kills the test before `with_accounts/2`
  # cleans up, leaving committed rows behind for every later test.
  defp safely(function) do
    fn ->
      try do
        function.()
      rescue
        error -> {:raised, error}
      end
    end
  end

  defp hold_uncommitted(function) do
    parent = self()

    task =
      Task.async(fn ->
        :ok = Sandbox.checkout(Repo, sandbox: false)

        try do
          Repo.transaction(fn ->
            result = function.()
            send(parent, {:uncommitted_held, self()})

            receive do
              :commit -> result
            end
          end)
        after
          Sandbox.checkin(Repo)
        end
      end)

    pid = task.pid
    assert_receive {:uncommitted_held, ^pid}, @db_task_ready_timeout
    task
  end

  defp lifecycle_attrs(account, workflow_job_id, fleet_name) do
    %{
      workflow_job_id: workflow_job_id,
      account_id: account.id,
      fleet_name: fleet_name,
      platform: "linux",
      vcpus: 1,
      memory_gb: 1,
      repository: "acme/cli"
    }
  end

  defp mark_running!(workflow_job_id, runner_name) do
    claim = Repo.one!(from(c in Claim, where: c.workflow_job_id == ^workflow_job_id))
    Claims.mark_running(workflow_job_id, runner_name, claim.claimed_at)
  end

  defp run_concurrently(functions) do
    tasks = Enum.map(functions, &prepare_db_task/1)

    tasks
    |> MapSet.new(& &1.pid)
    |> await_db_tasks(System.monotonic_time(:millisecond) + @db_task_ready_timeout)

    Enum.each(tasks, &send(&1.pid, :go))
    Task.await_many(tasks, 5_000)
  end

  defp await_db_tasks(pending_pids, deadline) do
    if MapSet.size(pending_pids) == 0 do
      :ok
    else
      timeout = max(deadline - System.monotonic_time(:millisecond), 0)

      receive do
        {:db_task_ready, pid} ->
          await_db_tasks(MapSet.delete(pending_pids, pid), deadline)
      after
        timeout ->
          flunk("database tasks did not become ready: #{inspect(pending_pids)}")
      end
    end
  end

  defp start_db_task(function) do
    task = prepare_db_task(function)
    pid = task.pid
    assert_receive {:db_task_ready, ^pid}, @db_task_ready_timeout
    send(pid, :go)
    task
  end

  defp prepare_db_task(function) do
    parent = self()

    Task.async(fn ->
      send(parent, {:db_task_ready, self()})

      receive do
        :go ->
          :ok = Sandbox.checkout(Repo, sandbox: false)

          try do
            function.()
          after
            Sandbox.checkin(Repo)
          end
      end
    end)
  end

  defp hold_platform_lock(account_id, platform) do
    parent = self()

    task =
      Task.async(fn ->
        :ok = Sandbox.checkout(Repo, sandbox: false)

        try do
          Repo.transaction(fn ->
            Repo.one!(
              from(limit in ConcurrencyLimit,
                where: limit.account_id == ^account_id and limit.platform == ^platform,
                lock: "FOR UPDATE"
              )
            )

            send(parent, {:platform_lock_held, self()})

            receive do
              :release -> :ok
            end
          end)
        after
          Sandbox.checkin(Repo)
        end
      end)

    pid = task.pid
    assert_receive {:platform_lock_held, ^pid}, @db_task_ready_timeout
    task
  end

  defp hold_uncommitted_claim(account_id, workflow_job_id, pod_name) do
    parent = self()

    task =
      Task.async(fn ->
        :ok = Sandbox.checkout(Repo, sandbox: false)

        try do
          Repo.transaction(fn ->
            {1, _rows} =
              Repo.insert_all(Claim, [
                %{
                  workflow_job_id: workflow_job_id,
                  account_id: account_id,
                  fleet_name: "conflicting-fleet",
                  pod_name: pod_name,
                  claimed_at: DateTime.utc_now(),
                  platform: :linux,
                  vcpus: 1,
                  memory_gb: 1,
                  lifecycle_state: "claimed",
                  runner_name: ""
                }
              ])

            send(parent, {:uncommitted_claim_inserted, self()})

            receive do
              :commit -> :committed
            end
          end)
        after
          Sandbox.checkin(Repo)
        end
      end)

    pid = task.pid
    assert_receive {:uncommitted_claim_inserted, ^pid}, @db_task_ready_timeout
    task
  end

  defp attempt_until_decided(workflow_job_id, account_id, fleet_name, pod_name, resources, retries \\ 500) do
    case Claims.attempt(workflow_job_id, account_id, fleet_name, pod_name, resources) do
      {:error, :account_busy} when retries > 0 ->
        Process.sleep(2)
        attempt_until_decided(workflow_job_id, account_id, fleet_name, pod_name, resources, retries - 1)

      result ->
        result
    end
  end

  defp with_accounts(count, function) do
    users = Enum.map(1..count, fn _index -> user_fixture(preload: [:account]) end)

    try do
      function.(Enum.map(users, & &1.account))
    after
      Enum.each(users, fn user ->
        Repo.delete!(user.account)
        Repo.delete!(user)
      end)
    end
  end
end
