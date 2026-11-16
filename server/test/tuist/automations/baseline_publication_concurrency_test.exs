defmodule Tuist.Automations.BaselinePublicationConcurrencyTest do
  use ExUnit.Case, async: false
  use Mimic

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Tuist.Automations
  alias Tuist.Automations.Alerts.Alert
  alias Tuist.Automations.Alerts.BaselineAttempt
  alias Tuist.Automations.Alerts.BaselineResult
  alias Tuist.IngestRepo
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.AutomationsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    :ok = Sandbox.checkout(Repo, sandbox: false)
    :ok = Sandbox.checkout(IngestRepo, sandbox: false)
    stub(Tuist.Tasks, :run_async, fn fun -> fun.() end)
    :ok
  end

  test "slow external actions allow cancellation while excluding a concurrent publisher" do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account: user.account)

    try do
      alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          baseline_established_at: nil,
          trigger_config: %{
            "threshold" => 10,
            "window_type" => "last_days",
            "window" => "30d",
            "apply_actions_to_existing_matches" => true
          }
        )

      [first, second] = Enum.sort([Ecto.UUID.generate(), Ecto.UUID.generate()])
      attempt = publishing_attempt(alert, [first, second])
      parent = self()

      {publisher, publisher_backend} =
        database_task(fn ->
          Automations.establish_alert_baseline(alert, & &1, fn _, id ->
            refute Repo.in_transaction?()
            send(parent, {:action_started, id})

            receive do
              :finish_action -> :ok
            end
          end)
        end)

      try do
        await_action(publisher, publisher_backend, first)

        # These are real separate database sessions, not a shared sandbox transaction.
        assert {:ok, :ok} =
                 Repo.transaction(fn ->
                   Repo.one!(from(a in Alert, where: a.id == ^alert.id, lock: "FOR UPDATE NOWAIT"))
                   Repo.one!(from(a in BaselineAttempt, where: a.id == ^attempt.id, lock: "FOR UPDATE NOWAIT"))
                   :ok
                 end)

        {competitor, competitor_backend} =
          database_task(fn ->
            Automations.establish_alert_baseline(alert, & &1, fn _, _ -> flunk("duplicate publisher") end)
          end)

        assert await_result(competitor, competitor_backend) == :ok

        assert {:ok, cancelled} =
                 Automations.update_alert(alert, %{
                   trigger_config: Map.put(alert.trigger_config, "apply_actions_to_existing_matches", false)
                 })

        refute cancelled.trigger_config["apply_actions_to_existing_matches"]
        send(publisher.pid, :finish_action)
        assert await_result(publisher, publisher_backend) == :ok
        assert Repo.reload!(attempt).last_published_test_case_id == first
        refute_received {:action_started, ^second}
        assert [%{test_case_id: ^first}] = Automations.list_active_alert_events(cancelled)

        # A new generation can acquire the released publication lock.
        {:ok, requested} =
          Automations.update_alert(cancelled, %{
            trigger_config: Map.put(cancelled.trigger_config, "apply_actions_to_existing_matches", true)
          })

        publishing_attempt(requested, [second])

        {next_publisher, next_publisher_backend} =
          database_task(fn ->
            Automations.establish_alert_baseline(requested, & &1, fn _, ^second -> :ok end)
          end)

        assert await_result(next_publisher, next_publisher_backend) == :ok
        assert Repo.reload!(requested).baseline_established_at
      after
        send(publisher.pid, :finish_action)
        Task.shutdown(publisher, 5000)
      end
    after
      Repo.delete!(project)
      Repo.delete!(user.account)
      Repo.delete!(user)
    end
  end

  # Runs `fun` in its own PostgreSQL session and returns the task with that
  # session's backend PID, so the test can see whether it waits on a lock.
  defp database_task(fun) do
    parent = self()

    task =
      Task.async(fn ->
        :ok = Sandbox.checkout(Repo, sandbox: false)
        :ok = Sandbox.checkout(IngestRepo, sandbox: false)
        %{rows: [[backend]]} = Repo.query!("SELECT pg_backend_pid()")
        send(parent, {:backend, self(), backend})

        try do
          fun.()
        after
          Sandbox.checkin(IngestRepo)
          Sandbox.checkin(Repo)
        end
      end)

    task_pid = task.pid

    receive do
      {:backend, ^task_pid, backend} -> {task, backend}
    end
  end

  # The test waits on progress, never on a deadline, so a slow runner only makes
  # it slower. The property under test is that no session waits on another's
  # lock, so a wait is detected directly in `pg_locks`: an ungranted lock stays
  # visible until it is granted, whatever the poll interval. A task that crashes
  # takes the linked test process down with it.
  defp await_action(%Task{ref: ref} = task, backend, test_case_id) do
    receive do
      {:action_started, ^test_case_id} -> :ok
      {^ref, result} -> flunk("publisher returned #{inspect(result)} before its first action")
    after
      10 ->
        refute_lock_wait(backend)
        await_action(task, backend, test_case_id)
    end
  end

  defp await_result(%Task{ref: ref} = task, backend) do
    receive do
      {^ref, result} ->
        Process.demonitor(ref, [:flush])
        result
    after
      10 ->
        refute_lock_wait(backend)
        await_result(task, backend)
    end
  end

  defp refute_lock_wait(backend) do
    %{rows: [[waiting]]} =
      Repo.query!("SELECT EXISTS (SELECT 1 FROM pg_locks WHERE pid = $1 AND NOT granted)", [backend])

    refute waiting, "database session #{backend} is waiting on a lock held by another session"
  end

  defp publishing_attempt(alert, ids) do
    {:ok, attempt} = Automations.begin_alert_baseline(alert)

    Repo.insert_all(
      BaselineResult,
      Enum.map(ids, fn id ->
        %{attempt_id: attempt.id, test_case_id: id, inserted_at: DateTime.utc_now(:second)}
      end)
    )

    attempt |> BaselineAttempt.changeset(%{state: "publishing"}) |> Repo.update!()
  end
end
