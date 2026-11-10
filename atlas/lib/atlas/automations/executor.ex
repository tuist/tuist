defmodule Atlas.Automations.Executor do
  @moduledoc "Fenced local step execution. Action results and progress commit together; claims survive worker failure."

  import Ecto.Query

  alias Atlas.Automations
  alias Atlas.Automations.Approval
  alias Atlas.Automations.Attempt
  alias Atlas.Automations.Catalog
  alias Atlas.Automations.Contract
  alias Atlas.Automations.Observability
  alias Atlas.Automations.Plan
  alias Atlas.Automations.Run
  alias Atlas.Automations.Tracing
  alias Atlas.Repo
  alias Atlas.Users

  require Logger

  def advance(id, job \\ nil) do
    case Repo.get(Run, id) do
      %Run{status: status} = run when status in ["queued", "running"] ->
        Tracing.with_run(run, "automation.worker", &delivery(&1, job))

      _ ->
        {:ok, :noop}
    end
  end

  def record_transport_failure(job, diagnostic) do
    case Repo.get(Run, job.args["run_id"]) do
      %Run{status: status} = root when status in ["queued", "running"] ->
        Tracing.with_run(root, "automation.worker.interrupted", fn _ ->
          Repo.transaction(fn -> transport_failure_locked(root.id, job, diagnostic) end)
        end)

      _ ->
        :ok
    end
  end

  defp transport_failure_locked(id, job, diagnostic) do
    run = lock_run(id)

    attempt =
      Repo.one(
        from(a in Attempt,
          where: a.run_id == ^id and a.status == "running" and a.job_id == ^job.id and a.job_attempt == ^job.attempt
        )
      )

    if attempt && run.status in ["queued", "running"] do
      Tracing.failure(diagnostic)

      attempt =
        Observability.complete!(attempt, "interrupted",
          error: "Worker process did not complete.",
          diagnostic: diagnostic
        )

      Observability.record!(run, "worker.exception",
        attempt: attempt,
        metadata: Map.put(Observability.job_metadata(job), "diagnostic", diagnostic)
      )

      worker_failure_state!(run, job)
    end
  end

  defp delivery(run, job) do
    Tracing.worker(job)
    Observability.record!(run, "worker.started", metadata: Observability.job_metadata(job))
    parent_span_id = Tracing.ids().span_id

    result =
      Tracing.span("automation.step", fn ->
        case prepare(run, job, parent_span_id) do
          {:ok, {:step, attempt, step}} -> execute_safely(run, attempt, step, job)
          {:ok, result} -> {:ok, result}
          {:error, _} -> failure(run, nil, job, :rollback, nil, [])
        end
      end)

    if match?({:ok, _}, result) do
      name = if result == {:ok, :busy}, do: "worker.busy", else: "worker.completed"
      Observability.record!(run, name, metadata: Observability.job_metadata(job))
    end

    result
  rescue
    exception -> failure(run, nil, job, :error, exception, __STACKTRACE__)
  catch
    kind, reason -> failure(run, nil, job, kind, reason, __STACKTRACE__)
  end

  defp prepare(root, job, parent_span_id) do
    Repo.transaction(fn ->
      run = lock_run(root.id)
      run = ensure_trace!(run, root)

      if run.status in ["queued", "running"] do
        case claim_available?(run, job) do
          true -> prepare_step(run, job, parent_span_id)
          false -> :busy
        end
      else
        :noop
      end
    end)
  end

  defp claim_available?(run, job) do
    case Repo.one(from(a in Attempt, where: a.run_id == ^run.id and a.status == "running")) do
      nil -> true
      attempt -> recoverable?(attempt, job) && interrupt!(run, attempt)
    end
  end

  defp recoverable?(attempt, %{id: id, attempt: number}) when not is_nil(id),
    do: attempt.job_id == id && number > (attempt.job_attempt || 0)

  defp recoverable?(_, _), do: false

  defp interrupt!(run, attempt) do
    interrupted = Observability.complete!(attempt, "interrupted", error: "Previous worker did not complete.")
    Observability.record!(run, "step.interrupted", attempt: interrupted)
    true
  end

  defp prepare_step(run, job, parent_span_id) do
    actor = Users.get_user(run.initiated_by_id)
    revision = Repo.preload(run, :revision).revision

    case Automations.authorize(actor, :write) do
      :ok ->
        case Enum.at(revision.plan["steps"], run.cursor) do
          nil ->
            run
            |> Ecto.Changeset.change(
              status: "succeeded",
              completed_at: Automations.now(),
              trace_completed_at: DateTime.utc_now()
            )
            |> Repo.update!()

            Observability.record!(run, "execution.succeeded")
            Automations.audit(actor, "execution.succeeded", run, "executions", interface: "worker")
            :finished

          step ->
            create_attempt(run, step, job, parent_span_id, actor)
        end

      _ ->
        fail_run!(run, "The execution user no longer has automation write permission.", actor)
        :finished
    end
  end

  defp create_attempt(run, step, job, parent_span_id, actor) do
    Tracing.step(step["id"])
    ids = Tracing.ids()
    started = DateTime.utc_now()
    input = Plan.resolve(step["inputs"], run.input, run.outputs)

    valid =
      case input do
        {:ok, value} when is_map(value) -> Contract.validate(%{"type" => "object"}, value) == :ok
        _ -> false
      end

    attempt =
      Repo.insert!(%Attempt{
        run_id: run.id,
        step_id: step["id"],
        status: "running",
        started_at: started,
        input: if(valid, do: elem(input, 1)),
        trace_id: ids.trace_id,
        span_id: ids.span_id,
        parent_span_id: parent_span_id,
        job_id: job && job.id,
        job_attempt: job && job.attempt
      })

    Observability.record!(run, "step.started", attempt: attempt, metadata: Observability.job_metadata(job))

    if valid do
      run |> Ecto.Changeset.change(status: "running", last_error: nil) |> Repo.update!()
      {:step, attempt, step}
    else
      fail_attempt!(run, attempt, "Step inputs must resolve to an object with no missing references.", actor, 0)
      :finished
    end
  end

  defp execute_safely(run, attempt, step, job) do
    Tracing.attempt(attempt)

    case Repo.transaction(fn -> execute_locked(run.id, attempt.id, step) end) do
      {:ok, result} ->
        {:ok, result}

      {:error, {:behavior_failed, reason, duration}} ->
        Repo.transaction(fn ->
          locked = lock_run(run.id)
          current = Repo.get!(Attempt, attempt.id)

          if locked.status == "running" and current.status == "running" do
            fail_attempt!(locked, current, reason, Users.get_user(locked.initiated_by_id), duration)
          end
        end)

      {:error, _} ->
        failure(run, attempt, job, :rollback, nil, [])
    end
  rescue
    exception -> failure(run, attempt, job, :error, exception, __STACKTRACE__)
  catch
    kind, reason -> failure(run, attempt, job, kind, reason, __STACKTRACE__)
  end

  defp execute_locked(id, attempt_id, step) do
    run = lock_run(id)
    attempt = Repo.get!(Attempt, attempt_id)

    if run.status == "running" && attempt.status == "running" do
      actor = Users.get_user(run.initiated_by_id)

      case Automations.authorize(actor, :write) do
        :ok -> perform(run, attempt, step, actor)
        _ -> fail_attempt!(run, attempt, "The execution user no longer has automation write permission.", actor, 0)
      end
    else
      :noop
    end
  end

  defp perform(run, attempt, %{"type" => "approval"} = step, actor) do
    approval =
      Repo.insert!(%Approval{
        run_id: run.id,
        step_id: step["id"],
        reviewer_id: step["reviewer_id"],
        payload: attempt.input
      })

    waiting_at = DateTime.utc_now()

    attempt =
      attempt
      |> Ecto.Changeset.change(
        status: "waiting_approval",
        wait_started_at: waiting_at,
        execution_duration_ms: Observability.elapsed(attempt.started_at, waiting_at)
      )
      |> Repo.update!()

    run |> Ecto.Changeset.change(status: "waiting_approval") |> Repo.update!()
    Observability.record!(run, "approval.requested", attempt: attempt, metadata: %{"approval_id" => approval.id})
    Automations.audit(actor, "approval.requested", run, "executions", interface: "worker")
  end

  defp perform(run, attempt, step, actor) do
    started = System.monotonic_time(:millisecond)
    result = Catalog.execute(step["behavior"], attempt.input, actor, run_id: run.id, step_id: step["id"])
    duration = max(System.monotonic_time(:millisecond) - started, 0)

    case result do
      {:ok, output} ->
        attempt = Observability.complete!(attempt, "succeeded", output: output, execution_duration_ms: duration)

        run
        |> Ecto.Changeset.change(
          status: "running",
          cursor: run.cursor + 1,
          outputs: Map.put(run.outputs, step["id"], output)
        )
        |> Repo.update!()

        Automations.enqueue!(run.id)
        Observability.record!(run, "step.succeeded", attempt: attempt, metadata: %{"execution_duration_ms" => duration})

        Automations.audit(actor, "step.succeeded", run, "executions",
          interface: "worker",
          metadata: %{"step_id" => step["id"]}
        )

      {:error, reason} ->
        error = if is_binary(reason), do: reason, else: "The behavior could not complete."
        Repo.rollback({:behavior_failed, error, duration})
    end
  end

  defp fail_attempt!(run, attempt, error, actor, duration) do
    attempt = Observability.complete!(attempt, "failed", error: error, execution_duration_ms: duration)
    Observability.record!(run, "step.failed", attempt: attempt)
    fail_run!(run, error, actor)
  end

  defp fail_run!(run, error, actor) do
    Tracing.error()

    run
    |> Ecto.Changeset.change(
      status: "failed",
      last_error: error,
      completed_at: Automations.now(),
      trace_completed_at: DateTime.utc_now()
    )
    |> Repo.update!()

    Observability.record!(run, "execution.failed")
    Automations.audit(actor, "execution.failed", run, "executions", interface: "worker")
  end

  defp failure(root, original_attempt, job, kind, reason, stacktrace) do
    Tracing.error()
    diagnostic = Observability.diagnostic(kind, reason, stacktrace)
    Tracing.failure(diagnostic)
    metadata = Map.put(Observability.job_metadata(job), "diagnostic", diagnostic)

    Logger.warning("Automation worker failed unexpectedly.",
      automation_run_id: root.id,
      trace_id: root.trace_id,
      span_id: Tracing.ids().span_id,
      automation_event: "worker.exception"
    )

    Repo.transaction(fn ->
      run = lock_run(root.id)
      attempt = original_attempt && Repo.get(Attempt, original_attempt.id)
      Observability.record!(run, "worker.exception", attempt: attempt, metadata: metadata)

      owns_transition =
        if attempt do
          attempt.status == "running"
        else
          run.cursor == root.cursor &&
            !Repo.exists?(from(a in Attempt, where: a.run_id == ^run.id and a.status == "running"))
        end

      if run.status in ["queued", "running"] && owns_transition do
        if attempt do
          failed =
            Observability.complete!(attempt, "failed", error: "Worker failed unexpectedly.", diagnostic: diagnostic)

          Observability.record!(run, "step.failed", attempt: failed)
        end

        worker_failure_state!(run, job)
      end
    end)

    {:error, :automation_worker_exception}
  rescue
    _ ->
      Logger.error("Automation worker diagnostics could not be persisted.", automation_run_id: root.id)
      {:error, :automation_worker_exception}
  catch
    _, _ -> {:error, :automation_worker_exception}
  end

  defp worker_failure_state!(run, %{attempt: number, max_attempts: max}) when number < max do
    run
    |> Ecto.Changeset.change(status: "queued", last_error: "Worker failed unexpectedly; transport retry pending.")
    |> Repo.update!()

    Observability.record!(run, "worker.retry_pending")
  end

  defp worker_failure_state!(run, _) do
    fail_run!(run, "Worker failed unexpectedly; retry limit reached.", Users.get_user(run.initiated_by_id))
    Observability.record!(run, "worker.exhausted")
  end

  defp lock_run(id), do: Repo.one!(from(r in Run, where: r.id == ^id, lock: "FOR UPDATE"))

  defp ensure_trace!(%Run{trace_id: nil} = run, root),
    do:
      run
      |> Ecto.Changeset.change(trace_id: root.trace_id, span_id: root.span_id, trace_flags: root.trace_flags)
      |> Repo.update!()

  defp ensure_trace!(run, _), do: run
end
