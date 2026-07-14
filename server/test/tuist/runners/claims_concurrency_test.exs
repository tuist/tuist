defmodule Tuist.Runners.ClaimsConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Tuist.Repo
  alias Tuist.Runners.Claim
  alias Tuist.Runners.Claims

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

    Enum.each(tasks, fn task ->
      assert_receive {:db_task_ready, pid} when pid == task.pid
    end)

    Enum.each(tasks, &send(&1.pid, :go))
    Task.await_many(tasks, 5_000)
  end

  defp start_db_task(function) do
    task = prepare_db_task(function)
    pid = task.pid
    assert_receive {:db_task_ready, ^pid}
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
    lock_key = if platform == :linux, do: account_id, else: -account_id

    task =
      Task.async(fn ->
        :ok = Sandbox.checkout(Repo, sandbox: false)

        try do
          Repo.transaction(fn ->
            Repo.query!("SELECT pg_advisory_xact_lock($1::bigint)", [lock_key])
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
    assert_receive {:platform_lock_held, ^pid}
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
