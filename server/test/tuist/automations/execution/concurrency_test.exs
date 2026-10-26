defmodule Tuist.Automations.Execution.ConcurrencyTest do
  use ExUnit.Case, async: false
  use Mimic

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Tuist.Automations.Execution
  alias Tuist.Automations.Execution.Delivery
  alias Tuist.Automations.Execution.Evaluation
  alias Tuist.Automations.Execution.TestState
  alias Tuist.Automations.Execution.Transition
  alias Tuist.Automations.Execution.Transitions
  alias Tuist.Automations.Monitors.FlakyTestsMonitor
  alias Tuist.IngestRepo
  alias Tuist.Repo
  alias Tuist.Tests
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.AutomationsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    :ok = Sandbox.checkout(Repo, sandbox: false)
    :ok = Sandbox.checkout(IngestRepo, sandbox: false)
    stub(Tuist.Tasks, :run_async, fn fun -> fun.() end)
    stub(Tests, :test_case_ids_with_successful_default_branch_run, fn _, ids, _ -> ids end)
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account: user.account)
    alert = AutomationsFixtures.automation_alert_fixture(project: project)
    {:ok, alert} = Execution.enable(alert.id)

    on_exit(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)
      runs = Repo.all(from(r in Evaluation, where: r.alert_id == ^alert.id, select: r.id))
      states = Repo.all(from(s in TestState, where: s.alert_id == ^alert.id, select: s.id))
      transitions = Repo.all(from(t in Transition, where: t.state_id in ^states, select: t.id))
      deliveries = Repo.all(from(d in Delivery, where: d.transition_id in ^transitions, select: d.id))

      Repo.delete_all(
        from(j in Oban.Job,
          where:
            fragment("?->>'evaluation_id'", j.args) in ^runs or fragment("?->>'transition_id'", j.args) in ^transitions or
              fragment("?->>'delivery_id'", j.args) in ^deliveries
        )
      )

      Repo.delete!(project)
      Repo.delete!(user.account)
      Repo.delete!(user)
    end)

    %{alert: alert}
  end

  test "two independent evaluators commit the same page only once", %{alert: alert} do
    parent = self()

    stub(FlakyTestsMonitor, :evaluate, fn _, ids ->
      send(parent, {:evaluating, self()})

      receive do
        :continue -> %{triggered: ids}
      after
        5000 -> flunk("evaluation was not released")
      end
    end)

    Execution.schedule(alert, %{"test_case_ids" => [Ecto.UUID.generate()]})
    run = Repo.one!(from(r in Evaluation, where: r.alert_id == ^alert.id))
    first = database_task(fn -> Execution.evaluate_page(run.id) end)
    second = database_task(fn -> Execution.evaluate_page(run.id) end)

    try do
      assert_receive {:evaluating, first_pid}, 5000
      assert_receive {:evaluating, second_pid}, 5000
      refute first_pid == second_pid
      send(first_pid, :continue)
      send(second_pid, :continue)
      assert Task.await(first, 5000) == :ok
      assert Task.await(second, 5000) == :ok
      states = Repo.all(from(s in TestState, where: s.alert_id == ^alert.id, select: s.id))
      assert Repo.aggregate(from(t in Transition, where: t.state_id in ^states), :count) == 1
      assert Repo.reload!(run).cursor == %{"offset" => 1}
    after
      Task.shutdown(first, :brutal_kill)
      Task.shutdown(second, :brutal_kill)
    end
  end

  test "a killed transition owner releases its lock and the prepared payload resumes", %{alert: alert} do
    parent = self()
    stub(FlakyTestsMonitor, :evaluate, fn _, ids -> %{triggered: ids} end)
    id = Ecto.UUID.generate()
    Execution.schedule(alert, %{"test_case_ids" => [id]})
    run = Repo.one!(from(r in Evaluation, where: r.alert_id == ^alert.id))
    Execution.evaluate_page(run.id)
    state = Repo.one!(from(s in TestState, where: s.alert_id == ^alert.id))
    transition = Repo.get!(Transition, state.pending_transition_id)

    stub(Tests, :prepare_automation_update, fn ^id, _, _ ->
      {:ok,
       %{
         "id" => id,
         "project_id" => alert.project_id,
         "name" => "test",
         "suite_name" => "suite",
         "module_name" => "module",
         "state" => "muted",
         "is_flaky" => false,
         "last_status" => "success"
       }, ["muted"]}
    end)

    stub(Tests, :write_automation_events, fn rows, _ ->
      send(parent, {:writing, self(), rows})

      receive do
        :continue -> :ok
      after
        5000 -> flunk("state write was not released")
      end
    end)

    first = database_task(fn -> Transitions.apply(transition.id) end)

    try do
      assert_receive {:writing, _, first_rows}, 5000
      competitor = database_task(fn -> Transitions.apply(transition.id) end)
      assert Task.await(competitor, 5000) == {:snooze, 1}
      assert Repo.reload!(transition).phase == "prepared"
      Task.shutdown(first, :brutal_kill)
      retry = database_task(fn -> Transitions.apply(transition.id) end)

      try do
        assert_receive {:writing, retry_pid, retry_rows}, 5000
        assert retry_rows == first_rows
        send(retry_pid, :continue)
        assert Task.await(retry, 5000) == :ok
        assert Repo.reload!(transition).phase == "applied"
      after
        Task.shutdown(retry, :brutal_kill)
      end
    after
      Task.shutdown(first, :brutal_kill)
    end
  end

  defp database_task(fun) do
    Task.async(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)
      :ok = Sandbox.checkout(IngestRepo, sandbox: false)

      try do
        fun.()
      after
        Sandbox.checkin(IngestRepo)
        Sandbox.checkin(Repo)
      end
    end)
  end

  test "losing the lock connection stops the owner instead of silently reconnecting" do
    key = "automation-lock-test:#{Ecto.UUID.generate()}"
    parent = self()

    owner =
      database_task(fn ->
        Execution.with_lock(key, fn ->
          send(parent, :lock_acquired)

          receive do
            :continue -> send(parent, :unfenced_work)
          after
            10_000 -> :ok
          end
        end)
      end)

    Process.unlink(owner.pid)

    try do
      assert_receive :lock_acquired, 5000

      %{rows: [[true]]} =
        Repo.query!(
          """
          SELECT pg_terminate_backend(pid) FROM pg_locks
          WHERE locktype = 'advisory' AND granted
            AND classid = ((hashtextextended($1, 0) >> 32) & 4294967295)::oid
            AND objid = (hashtextextended($1, 0) & 4294967295)::oid
          """,
          [key]
        )

      assert {:exit, _} = Task.yield(owner, 5000)
      refute_received :unfenced_work
      assert :ok = Execution.with_lock(key, fn -> :ok end)
    after
      Task.shutdown(owner, :brutal_kill)
    end
  end
end
