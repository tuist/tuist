defmodule Tuist.Runners.PrepaidNotificationConcurrencyTest do
  use ExUnit.Case, async: false
  use Mimic

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Tuist.Accounts.UserNotifier
  alias Tuist.Repo
  alias Tuist.Runners.Allowance
  alias Tuist.Runners.Prepaid
  alias Tuist.Runners.PrepaidActivation
  alias Tuist.Runners.PrepaidNotification
  alias Tuist.Runners.PrepaidNotifications
  alias Tuist.Runners.RunnerSession
  alias Tuist.Runners.Workers.PrepaidNotificationWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures

  setup do
    stub(UserNotifier, :deliver_runner_prepaid_notification, fn _, _, _ -> flunk("unexpected email delivery") end)
    :ok = Sandbox.checkout(Repo, sandbox: false)
    # The notifications count remote execution usage too, read from
    # ClickHouse by the independent sessions, so they need an unsandboxed
    # connection. The account is fresh, so it reads no other test's rows.
    ingest_repo = Sandbox.start_owner!(Tuist.IngestRepo, shared: true, sandbox: false)
    on_exit(fn -> Sandbox.stop_owner(ingest_repo) end)
    user = AccountsFixtures.user_fixture()
    account = user.account |> Ecto.Changeset.change(runner_trial_started_at: nil) |> Repo.update!()
    now = DateTime.truncate(DateTime.utc_now(), :second)
    start = DateTime.add(now, -2, :day)

    BillingFixtures.subscription_fixture(
      account_id: account.id,
      current_period_start: DateTime.add(now, -10, :day),
      current_period_end: DateTime.add(now, 20, :day)
    )

    activation =
      Repo.insert!(%PrepaidActivation{
        account_id: account.id,
        change_id: Ecto.UUID.generate(),
        principal: %{},
        before: %{},
        status: "applied",
        activated_at: start,
        request: %{
          "starts_on" => Date.to_iso8601(DateTime.to_date(start)),
          "expires_on" => now |> DateTime.to_date() |> Date.add(30) |> Date.to_iso8601(),
          "paid_cents" => 100,
          "credit_multiplier" => "1",
          "platforms" => ["macos"]
        }
      })

    minutes =
      Allowance.free_monthly_minutes(:macos) + div(100, Prepaid.on_demand_cost_for_milliseconds(:macos, 60_000).amount)

    start_usec = %{start | microsecond: {0, 6}}

    Repo.insert!(%RunnerSession{
      account_id: account.id,
      workflow_job_id: System.unique_integer([:positive]),
      fleet_name: "prepaid-concurrency",
      platform: :macos,
      vcpus: 8,
      memory_gb: 24,
      billing_multiplier: 10_000,
      started_at: start_usec,
      ended_at: DateTime.add(start_usec, minutes, :minute),
      job_started_at: start_usec,
      job_ended_at: DateTime.add(start_usec, minutes, :minute)
    })

    on_exit(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)

      try do
        ids = Repo.all(from(n in PrepaidNotification, where: n.activation_id == ^activation.id, select: n.id))
        worker = Oban.Worker.to_string(PrepaidNotificationWorker)

        for id <- ids do
          args = %{"notification_id" => id}
          Repo.delete_all(from(j in Oban.Job, where: j.worker == ^worker and j.args == ^args))
        end

        Repo.delete!(account)
        Repo.delete!(user)
      after
        Sandbox.checkin(Repo)
      end
    end)

    %{activation: activation}
  end

  test "independent database sessions serialize enqueue and create only one recipient job", %{activation: activation} do
    parent = self()

    first =
      database_task(fn ->
        Repo.transaction(fn ->
          assert {:ok, _} = PrepaidNotifications.enqueue(activation.id)
          send(parent, :enqueue_uncommitted)

          receive do
            :release -> :ok
          after
            5_000 -> Repo.rollback(:release_timeout)
          end
        end)
      end)

    try do
      assert_receive :enqueue_uncommitted, 5_000
      second = competing_task(parent, fn -> PrepaidNotifications.enqueue(activation.id) end)

      try do
        assert_receive {:competing_backend, backend}, 5_000
        assert wait_until_blocked(backend, 500)
        send(first.pid, :release)
        assert {:ok, :ok} = Task.await(first, 5_000)
        assert {:ok, _} = Task.await(second, 5_000)
        assert [notification] = Repo.all(from(n in PrepaidNotification, where: n.activation_id == ^activation.id))
        worker = Oban.Worker.to_string(PrepaidNotificationWorker)
        args = %{"notification_id" => notification.id}
        assert Repo.aggregate(from(j in Oban.Job, where: j.worker == ^worker and j.args == ^args), :count) == 1
      after
        Task.shutdown(second, :brutal_kill)
      end
    after
      send(first.pid, :release)
      Task.shutdown(first, :brutal_kill)
    end
  end

  test "duplicate delivery jobs on independent sessions do not concurrently send the same email", %{
    activation: activation
  } do
    {:ok, _} = PrepaidNotifications.enqueue(activation.id)
    notification = Repo.one!(from(n in PrepaidNotification, where: n.activation_id == ^activation.id))
    parent = self()

    stub(UserNotifier, :deliver_runner_prepaid_notification, fn _, _, _ ->
      send(parent, :external_send)

      receive do
        :release -> {:ok, :email}
      after
        5_000 -> {:error, :release_timeout}
      end
    end)

    job = %Oban.Job{args: %{"notification_id" => notification.id}}
    first = database_task(fn -> PrepaidNotificationWorker.perform(job) end)

    try do
      assert_receive :external_send, 5_000
      second = competing_task(parent, fn -> PrepaidNotificationWorker.perform(job) end)

      try do
        assert_receive {:competing_backend, backend}, 5_000
        assert wait_until_blocked(backend, 500)
        send(first.pid, :release)
        assert :ok = Task.await(first, 5_000)
        assert :ok = Task.await(second, 5_000)
        refute_receive :external_send
        assert Repo.reload!(notification).delivered_at
      after
        Task.shutdown(second, :brutal_kill)
      end
    after
      send(first.pid, :release)
      Task.shutdown(first, :brutal_kill)
    end
  end

  defp competing_task(parent, function) do
    database_task(fn ->
      %{rows: [[backend]]} = Repo.query!("SELECT pg_backend_pid()")
      send(parent, {:competing_backend, backend})
      function.()
    end)
  end

  defp database_task(function) do
    owner = self()

    Task.async(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)
      Mimic.allow(UserNotifier, owner, self())

      try do
        function.()
      after
        Sandbox.checkin(Repo)
      end
    end)
  end

  defp wait_until_blocked(_backend, 0), do: false

  defp wait_until_blocked(backend, attempts) do
    case Repo.query!("SELECT cardinality(pg_blocking_pids($1)) > 0", [backend]) do
      %{rows: [[true]]} ->
        true

      %{rows: [[false]]} ->
        Process.sleep(10)
        wait_until_blocked(backend, attempts - 1)
    end
  end
end
