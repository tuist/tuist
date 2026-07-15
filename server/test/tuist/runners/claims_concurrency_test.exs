defmodule Tuist.Runners.ClaimsConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Tuist.Repo
  alias Tuist.Runners.Claim
  alias Tuist.Runners.Claims
  alias Tuist.Runners.ConcurrencyLimit

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
      :ok = Sandbox.checkout(Repo, sandbox: false)
      send(parent, {:db_task_ready, self()})

      try do
        receive do
          :go -> function.()
        end
      after
        Sandbox.checkin(Repo)
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
