defmodule Atlas.Automations.Tracing do
  @moduledoc "W3C trace context carried across durable admissions, worker deliveries and approval decisions."

  alias OpenTelemetry.Ctx
  alias OpenTelemetry.Span
  alias OpenTelemetry.Tracer

  require Tracer

  def span(name, fun, opts \\ %{}) do
    parent = Ctx.get_current()
    parent_span = Tracer.current_span_ctx(parent)
    span = Tracer.start_span(parent, name, Map.put(opts, :kind, :internal))
    span = recording_or_fallback(span, parent_span)
    token = parent |> Tracer.set_current_span(span) |> Ctx.attach()

    try do
      fun.()
    after
      Span.end_span(span)
      Ctx.detach(token)
    end
  end

  def with_run(run, name, fun, opts \\ %{}) do
    root = %{
      run
      | trace_id: run.trace_id || random_id(16),
        span_id: run.span_id || random_id(8)
    }

    context =
      :otel_tracer.from_remote_span(
        String.to_integer(root.trace_id, 16),
        String.to_integer(root.span_id, 16),
        root.trace_flags
      )

    token = Ctx.new() |> Tracer.set_current_span(context) |> Ctx.attach()

    try do
      span(
        name,
        fn ->
          Tracer.set_attribute("automation.run_id", run.id)
          fun.(root)
        end,
        opts
      )
    after
      Ctx.detach(token)
    end
  end

  def wait_options(nil), do: %{}

  def wait_options(started) do
    timestamp =
      System.convert_time_unit(DateTime.to_unix(started, :microsecond), :microsecond, :native) -
        System.time_offset(:native)

    %{start_time: min(timestamp, System.monotonic_time())}
  end

  def ids do
    case Tracer.current_span_ctx() do
      :undefined ->
        %{trace_id: nil, span_id: nil, trace_flags: 0}

      span ->
        %{
          trace_id: String.pad_leading(Span.hex_trace_id(span), 32, "0"),
          span_id: String.pad_leading(Span.hex_span_id(span), 16, "0"),
          trace_flags: String.to_integer(Span.hex_span_ctx(span).otel_trace_flags, 16)
        }
    end
  end

  def step(id), do: Tracer.set_attribute("automation.step_id", id)
  def error, do: Tracer.set_status(:error, "Automation operation failed")

  def failure(diagnostic) do
    error()

    Tracer.add_event("exception", %{
      "exception.type" => diagnostic["exception_type"] || diagnostic["kind"],
      "exception.stacktrace" => JSON.encode!(diagnostic["frames"]),
      "exception.escaped" => false
    })
  end

  def worker(job) do
    if job do
      Tracer.set_attributes(%{
        "automation.job.attempt" => job.attempt,
        "automation.job.max_attempts" => job.max_attempts
      })

      if job.id, do: Tracer.set_attribute("automation.job.id", job.id)
    end
  end

  def attempt(attempt) do
    Tracer.set_attributes(%{"automation.attempt_id" => attempt.id, "automation.executor" => attempt.executor})
  end

  def admission(run) do
    Tracer.set_attributes(%{"automation.run_id" => run.id, "automation.revision_id" => run.revision_id})
  end

  def event(name) do
    Tracer.add_event(name, %{})
  end

  defp recording_or_fallback(span, parent) do
    if span_number(span) == 0 || span_number(span) == span_number(parent) do
      trace = if trace_number(parent) == 0, do: String.to_integer(random_id(16), 16), else: trace_number(parent)

      flags =
        if trace_number(parent) == 0, do: 1, else: String.to_integer(Span.hex_span_ctx(parent).otel_trace_flags, 16)

      :otel_tracer.non_recording_span(trace, String.to_integer(random_id(8), 16), flags)
    else
      span
    end
  end

  defp span_number(:undefined), do: 0
  defp span_number(span), do: Span.span_id(span)
  defp trace_number(:undefined), do: 0
  defp trace_number(span), do: Span.trace_id(span)
  defp random_id(bytes), do: bytes |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
end
