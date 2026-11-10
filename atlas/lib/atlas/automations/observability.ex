defmodule Atlas.Automations.Observability do
  @moduledoc "Payload-free, durable execution events and bounded worker diagnostics."

  import Ecto.Query

  alias Atlas.Automations.Attempt
  alias Atlas.Automations.Event
  alias Atlas.Automations.Notifier
  alias Atlas.Automations.Run
  alias Atlas.Automations.Tracing
  alias Atlas.Repo

  require Logger

  @messages %{
    "execution.queued" => "Execution admitted and queued.",
    "execution.succeeded" => "Execution completed successfully.",
    "execution.failed" => "Execution failed.",
    "execution.retried" => "Execution retry requested.",
    "execution.cancelled" => "Execution cancelled.",
    "worker.started" => "Worker delivery started.",
    "worker.completed" => "Worker delivery completed.",
    "worker.busy" => "Another worker owns the active step; delivery deferred.",
    "worker.exception" => "Worker delivery failed unexpectedly. Step state identifies committed progress.",
    "worker.retry_pending" => "Worker failure is eligible for a transport retry.",
    "worker.exhausted" => "Worker retry limit reached; execution failed.",
    "step.started" => "Step execution started.",
    "step.succeeded" => "Step completed successfully.",
    "step.failed" => "Step failed.",
    "step.interrupted" => "Previous worker was interrupted; step recovered by a later delivery.",
    "approval.requested" => "Execution paused for approval.",
    "approval.approved" => "Reviewer approved the persisted payload.",
    "approval.rejected" => "Reviewer rejected the persisted payload."
  }
  @metadata ~w(job_id job_attempt max_attempts actor_id approval_id reason execution_duration_ms wait_duration_ms diagnostic)

  def record!(run, name, opts \\ []) do
    message = Map.fetch!(@messages, name)
    ids = Tracing.ids()
    attempt = opts[:attempt]

    level =
      if name in ~w(execution.failed worker.exception worker.exhausted step.failed step.interrupted),
        do: "warning",
        else: "info"

    metadata = Map.take(Keyword.get(opts, :metadata, %{}), @metadata)

    {:ok, event} =
      Repo.transaction(fn ->
        {1, [sequence]} =
          Repo.update_all(from(r in Run, where: r.id == ^run.id, select: r.event_sequence), inc: [event_sequence: 1])

        event =
          Repo.insert!(%Event{
            sequence: sequence,
            run_id: run.id,
            attempt_id: attempt && attempt.id,
            step_id: attempt && attempt.step_id,
            event: name,
            message: message,
            level: level,
            trace_id: run.trace_id || ids.trace_id,
            span_id: ids.span_id || (attempt && attempt.span_id),
            metadata: metadata
          })

        Notifier.changed(run.id)
        event
      end)

    Tracing.event(name)

    if !Repo.in_transaction?() do
      Logger.log(String.to_existing_atom(level), message,
        automation_run_id: run.id,
        automation_step_id: event.step_id,
        trace_id: event.trace_id,
        span_id: event.span_id,
        automation_event: name
      )
    end

    event
  end

  def complete!(%Attempt{} = attempt, status, attrs \\ []) do
    finished = DateTime.utc_now()
    wait_ms = if attempt.wait_started_at, do: elapsed(attempt.wait_started_at, finished)

    attempt
    |> Ecto.Changeset.change(
      Keyword.merge(
        [
          status: status,
          completed_at: finished,
          duration_ms: elapsed(attempt.started_at, finished),
          wait_duration_ms: wait_ms
        ],
        attrs
      )
    )
    |> Repo.update!()
  end

  def diagnostic(kind, reason, stacktrace) do
    %{
      "kind" => Atom.to_string(kind),
      "exception_type" => exception_type(reason),
      "frames" => if(is_list(stacktrace), do: stacktrace, else: []) |> Enum.take(10) |> Enum.map(&frame/1)
    }
  end

  def job_metadata(nil), do: %{}
  def job_metadata(job), do: %{"job_id" => job.id, "job_attempt" => job.attempt, "max_attempts" => job.max_attempts}
  def elapsed(nil, _), do: nil
  def elapsed(first, last), do: max(DateTime.diff(last, first, :microsecond), 0) |> div(1000)

  defp exception_type(%{__exception__: true, __struct__: module}),
    do: module |> Atom.to_string() |> String.slice(0, 128)

  defp exception_type(_), do: nil

  defp frame({module, function, arguments, location}) when is_atom(module) and is_atom(function) do
    %{
      "module" => Atom.to_string(module),
      "function" => Atom.to_string(function),
      "arity" => if(is_list(arguments), do: length(arguments), else: arguments),
      "line" => Keyword.get(location, :line)
    }
  end

  defp frame(_), do: %{}
end
