defmodule Atlas.Automations.ObservabilityTest do
  use Atlas.DataCase, async: true
  use Mimic

  import Atlas.AutomationsFixtures
  import Atlas.MCP.ToolCase, only: [insert_user!: 1]
  import ExUnit.CaptureLog

  alias Atlas.Automations
  alias Atlas.Automations.Approval
  alias Atlas.Automations.Attempt
  alias Atlas.Automations.Event
  alias Atlas.Automations.Executor
  alias Atlas.Automations.Observability
  alias Atlas.Automations.Run
  alias Atlas.Automations.Tracing
  alias Atlas.Repo
  alias Atlas.Tasks.Task
  alias OpenTelemetry.Tracer

  setup do
    %{actor: insert_user!(%{scopes: ["automation:write", "tasks:write"]})}
  end

  test "durable ordered events, real span identities and precise timings", %{actor: actor} do
    original = Tracer.current_span_ctx()

    Tracing.span("test.parent", fn ->
      parent = Tracing.ids()
      {workflow, _} = workflow_fixture(actor)
      {:ok, run} = Automations.run_workflow(actor, workflow.id, %{})
      assert run.trace_id == parent.trace_id
      refute run.span_id == parent.span_id
      assert Tracing.ids() == parent
      assert {:ok, _} = Executor.advance(run.id)
      assert {:ok, _} = Executor.advance(run.id)
      assert Tracing.ids() == parent
      {:ok, finished} = Automations.get_run(actor, run.id)
      assert finished.status == "succeeded"
      assert finished.trace_completed_at
      [attempt] = finished.attempts
      assert attempt.trace_id == run.trace_id
      assert byte_size(attempt.span_id) == 16
      refute attempt.span_id == attempt.parent_span_id
      assert attempt.started_at && attempt.completed_at
      assert attempt.duration_ms >= 0 && attempt.execution_duration_ms >= 0
      assert is_nil(attempt.wait_duration_ms)
      {:ok, {events, _}} = Automations.execution_events(actor, run.id)
      assert Enum.map(events, & &1.sequence) == Enum.to_list(length(events)..1//-1)
      assert Enum.any?(events, &(&1.event == "execution.succeeded"))
    end)

    assert Tracer.current_span_ctx() == original
  end

  test "approval waiting is measured separately and preserves exact output", %{actor: actor} do
    {workflow, _} =
      workflow_fixture(actor, [
        %{
          "id" => "review",
          "type" => "approval",
          "reviewer_id" => actor.id,
          "inputs" => %{"private" => "private-payload-value"}
        }
      ])

    {:ok, run} = Automations.run_workflow(actor, workflow.id, %{})
    Executor.advance(run.id)
    approval = Repo.get_by!(Approval, run_id: run.id)
    waiting = Repo.get_by!(Attempt, run_id: run.id)
    assert waiting.wait_started_at && is_nil(waiting.completed_at)
    assert {:ok, _} = Automations.decide_approval(actor, approval.id, "approved")
    finished = Repo.get!(Attempt, waiting.id)
    assert finished.wait_duration_ms >= 0
    assert finished.completed_at && finished.output == approval.payload
    {:ok, trace} = Automations.execution_trace(actor, run.id)
    refute Jason.encode!(trace) =~ "private-payload-value"
    assert Enum.any?(trace.events, &(&1.event == "approval.approved"))
  end

  test "unexpected exceptions survive action rollback and never copy their messages", %{actor: actor} do
    {workflow, _} =
      workflow_fixture(actor, [
        %{"id" => "task", "behavior" => "tasks.create", "inputs" => %{"title" => "private-task-title"}}
      ])

    {:ok, run} = Automations.run_workflow(actor, workflow.id, %{"secret" => "input-secret"})

    stub(Repo, :update!, fn
      %Ecto.Changeset{data: %Attempt{}, changes: %{status: "succeeded"}} = change ->
        Mimic.call_original(Repo, :update!, [change])
        raise "exception-secret"

      change ->
        Mimic.call_original(Repo, :update!, [change])
    end)

    log =
      capture_log(fn ->
        assert {:error, :automation_worker_exception} = Executor.advance(run.id, job(run.id, 1))
      end)

    assert Repo.aggregate(Task, :count) == 0
    failed = Repo.get_by!(Attempt, run_id: run.id)
    assert failed.status == "failed" && failed.started_at && failed.completed_at
    assert failed.diagnostic["exception_type"] == "Elixir.RuntimeError"
    assert Repo.get!(Run, run.id).status == "queued"
    {:ok, trace} = Automations.execution_trace(actor, run.id)

    for secret <- ["exception-secret", "private-task-title", "input-secret"] do
      refute log =~ secret
      refute Jason.encode!(trace) =~ secret
    end

    assert Enum.any?(trace.events, &(&1.event == "worker.retry_pending"))
    stub(Repo, :update!, &Mimic.call_original(Repo, :update!, [&1]))
    assert {:ok, _} = Executor.advance(run.id, job(run.id, 2))
    Executor.advance(run.id, job(run.id, 3))
    assert Repo.aggregate(Task, :count) == 1
    assert Repo.get!(Run, run.id).last_error == nil
    assert Repo.aggregate(Attempt, :count) == 2
  end

  test "the last failed delivery marks the run failed", %{actor: actor} do
    {workflow, _} = workflow_fixture(actor)
    {:ok, run} = Automations.run_workflow(actor, workflow.id, %{})

    stub(Repo, :insert!, fn
      %Attempt{} -> raise "not persisted"
      record -> Mimic.call_original(Repo, :insert!, [record])
    end)

    capture_log(fn -> assert {:error, _} = Executor.advance(run.id, job(run.id, 5)) end)
    assert Repo.get!(Run, run.id).status == "failed"
    assert Repo.get!(Run, run.id).trace_completed_at
    assert Repo.exists?(from(e in Event, where: e.run_id == ^run.id and e.event == "worker.exhausted"))
  end

  test "a later delivery recovers an interrupted claim but another job cannot steal it", %{actor: actor} do
    {workflow, _} = workflow_fixture(actor)
    {:ok, run} = Automations.run_workflow(actor, workflow.id, %{})
    lost = claim(run, 501, 1)
    assert {:ok, :busy} = Executor.advance(run.id, %{job(run.id, 1) | id: 502})
    assert Repo.get!(Attempt, lost.id).status == "running"
    assert {:ok, _} = Executor.advance(run.id, job(run.id, 2))
    assert Repo.get!(Attempt, lost.id).status == "interrupted"
    assert Repo.aggregate(Attempt, :count) == 2
  end

  test "Oban process-loss telemetry is recorded once and only for its owned claim", %{actor: actor} do
    {workflow, _} = workflow_fixture(actor)
    {:ok, run} = Automations.run_workflow(actor, workflow.id, %{})
    attempt = claim(run, 501, 5)

    metadata = %{
      job: job(run.id, 5),
      reason: %RuntimeError{message: "sensitive"},
      stacktrace: [{__MODULE__, :test, ["sensitive"], [line: 8]}]
    }

    :telemetry.execute([:oban, :job, :exception], %{}, %{metadata | job: %{metadata.job | id: 502}})
    assert Repo.get!(Attempt, attempt.id).status == "running"
    :telemetry.execute([:oban, :job, :exception], %{}, metadata)
    :telemetry.execute([:oban, :job, :exception], %{}, metadata)
    assert Repo.get!(Run, run.id).status == "failed"
    assert Repo.get!(Attempt, attempt.id).status == "interrupted"
    assert Repo.aggregate(from(e in Event, where: e.event == "worker.exception"), :count) == 1
    {:ok, trace} = Automations.execution_trace(actor, run.id)
    refute Jason.encode!(trace) =~ "sensitive"
  end

  test "cancelling a committed claim fences off a subsequent worker", %{actor: actor} do
    {workflow, _} = workflow_fixture(actor)
    {:ok, run} = Automations.run_workflow(actor, workflow.id, %{})
    attempt = claim(run, 501, 1)
    assert {:ok, _} = Automations.control_run(actor, run.id, "cancel")
    assert {:ok, :noop} = Executor.advance(run.id, job(run.id, 2))
    assert Repo.get!(Attempt, attempt.id).status == "cancelled"
    assert Repo.get!(Attempt, attempt.id).completed_at
    assert Repo.get!(Run, run.id).outputs == %{}
  end

  test "reads are scoped, paginated and independent of event timestamps", %{actor: actor} do
    {workflow, _} = workflow_fixture(actor)
    {:ok, run} = Automations.run_workflow(actor, workflow.id, %{})
    for _ <- 1..25, do: Observability.record!(run, "worker.started")
    {:ok, {events, meta}} = Automations.execution_events(actor, run.id)
    assert length(events) == 20 && meta.total_count == 26
    first = hd(events)
    first |> Ecto.Changeset.change(inserted_at: ~U[2000-01-01 00:00:00.000000Z]) |> Repo.update!()
    {:ok, {[still_first | _], _}} = Automations.execution_events(actor, run.id)
    assert still_first.id == first.id
    {:ok, {older, _}} = Automations.execution_events(actor, run.id, %{"page" => 2})
    assert length(older) == 6
    assert {:error, :forbidden} = Automations.execution_trace(insert_user!(%{}), run.id)
    assert {:ok, _} = Automations.execution_trace(insert_user!(%{scopes: ["automation:read"]}), run.id)
  end

  test "cancellation between claim commit and action commit fences the old worker", %{actor: actor} do
    {workflow, _} =
      workflow_fixture(actor, [
        %{"id" => "task", "behavior" => "tasks.create", "inputs" => %{"title" => "Must not run"}}
      ])

    {:ok, run} = Automations.run_workflow(actor, workflow.id, %{})

    stub(Repo, :transaction, fn callback ->
      result = Mimic.call_original(Repo, :transaction, [callback])

      case result do
        {:ok, {:step, _, _}} -> assert {:ok, _} = Automations.control_run(actor, run.id, "cancel")
        _ -> :ok
      end

      result
    end)

    assert {:ok, :noop} = Executor.advance(run.id, job(run.id, 1))
    assert Repo.aggregate(Task, :count) == 0
    assert Repo.get_by!(Attempt, run_id: run.id).status == "cancelled"
  end

  test "a post-commit diagnostic failure never replays an action or fails committed progress", %{actor: actor} do
    {workflow, _} =
      workflow_fixture(actor, [%{"id" => "task", "behavior" => "tasks.create", "inputs" => %{"title" => "Once only"}}])

    {:ok, run} = Automations.run_workflow(actor, workflow.id, %{})

    stub(Repo, :insert!, fn
      %Event{event: "worker.completed"} -> raise "post-commit failure"
      record -> Mimic.call_original(Repo, :insert!, [record])
    end)

    capture_log(fn -> assert {:error, _} = Executor.advance(run.id, job(run.id, 5)) end)
    assert Repo.get!(Run, run.id).cursor == 1
    assert Repo.get!(Run, run.id).status == "running"
    assert Repo.aggregate(Task, :count) == 1
    stub(Repo, :insert!, &Mimic.call_original(Repo, :insert!, [&1]))
    assert {:ok, _} = Executor.advance(run.id, job(run.id, 1))
    assert Repo.get!(Run, run.id).status == "succeeded"
    assert Repo.aggregate(Task, :count) == 1
  end

  test "diagnostics strip argument values and retain measured zero" do
    diagnostic = Observability.diagnostic(:throw, "secret", [{__MODULE__, :call, ["secret"], [line: 1]}])

    assert diagnostic["frames"] == [
             %{"module" => Atom.to_string(__MODULE__), "function" => "call", "arity" => 1, "line" => 1}
           ]

    refute Jason.encode!(diagnostic) =~ "secret"
    assert Observability.elapsed(~U[2026-01-01 00:00:00.000000Z], ~U[2026-01-01 00:00:00.000000Z]) == 0
    assert Observability.elapsed(nil, DateTime.utc_now()) == nil
  end

  defp job(id, number),
    do: %Oban.Job{
      id: 501,
      args: %{"run_id" => id},
      attempt: number,
      max_attempts: 5,
      worker: "Atlas.Automations.Workers.ExecuteRun"
    }

  defp claim(run, job_id, number) do
    run |> Ecto.Changeset.change(status: "running") |> Repo.update!()

    Repo.insert!(%Attempt{
      run_id: run.id,
      step_id: "value",
      status: "running",
      started_at: DateTime.utc_now(),
      job_id: job_id,
      job_attempt: number
    })
  end
end
