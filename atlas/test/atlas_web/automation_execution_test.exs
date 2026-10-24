defmodule AtlasWeb.AutomationExecutionTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Atlas.Automations.Attempt
  alias Atlas.Automations.Run
  alias AtlasWeb.AutomationExecution

  test "legacy timings are absent rather than measured zero" do
    run = %Run{
      id: "legacy",
      inserted_at: ~U[2026-01-01 00:00:00Z],
      attempts: [%Attempt{id: "step", step_id: "value", status: "succeeded"}]
    }

    html = render_component(&AutomationExecution.execution_observability/1, run: run, events: [])
    assert html =~ "Not recorded"
    refute html =~ "data-part=\"trace-segment\""
    assert AutomationExecution.duration_label(nil) == "—"
    assert AutomationExecution.duration_label(0) == "0 ms"
  end

  test "approval traces have a time axis and separate proportional processing and waiting lanes" do
    html = render_trace(timed_run(wait_started_at: ~U[2026-01-01 00:00:00.059000Z], wait_duration_ms: 5061))
    dom = LazyHTML.from_fragment(html)
    assert html =~ "Timeline (since admission)"
    assert html =~ "2.56 s" && html =~ "5.12 s"
    assert LazyHTML.query(dom, "[data-part='trace-phase-row']") |> Enum.count() == 2

    assert LazyHTML.query(dom, "[data-part='trace-phase-row'][data-phase='execution'] [data-part='trace-segment']")
           |> LazyHTML.attribute("style") == ["left: 0.0%; width: 1.1523%;"]

    assert LazyHTML.query(dom, "[data-part='trace-phase-row'][data-phase='waiting'] [data-part='trace-segment']")
           |> LazyHTML.attribute("style") == ["left: 1.1523%; width: 98.8477%;"]

    assert html =~ "Processing: 59 ms, starting 0 ms after admission"
    refute html =~ "data-part=\"trace-legend\""
  end

  test "tiny and zero-length intervals are not inflated to a percentage minimum" do
    for {ended, width, label} <- [
          {~U[2026-01-01 00:00:00.000005Z], "0.0001", "5 µs"},
          {~U[2026-01-01 00:00:00.000000Z], "0.0", "0 ms"}
        ] do
      html = render_trace(timed_run(completed_at: ended, duration_ms: 0))
      assert html =~ "width: #{width}%;"
      assert html =~ "Processing: #{label}, starting 0 ms after admission"
    end
  end

  test "all attempts share the admission axis and have distinct DOM IDs" do
    run = timed_run()
    second = %{hd(run.attempts) | id: "second", step_id: "second", started_at: ~U[2026-01-01 00:00:02.560000Z]}
    html = render_trace(%{run | attempts: run.attempts ++ [second]})
    dom = LazyHTML.from_fragment(html)

    assert LazyHTML.query(dom, "#execution-waterfall tbody > tr") |> LazyHTML.attribute("id") == [
             "execution-trace-first",
             "execution-trace-second"
           ]

    assert LazyHTML.query(dom, "#execution-trace-second [data-part='trace-segment']") |> LazyHTML.attribute("style") ==
             ["left: 50.0%; width: 50.0%;"]

    assert LazyHTML.query(dom, "[data-part='trace-axis'] [data-position='100']") |> Enum.count() == 2
  end

  test "missing terminal attempt timings are not inferred from workflow completion" do
    html = render_trace(timed_run(completed_at: nil, duration_ms: nil))
    assert html =~ "Not recorded"
    refute html =~ "data-part=\"trace-segment\""
  end

  test "an ongoing approval wait extends to the current trace window without inventing a completed duration" do
    first = DateTime.add(DateTime.utc_now(), -5_120_000, :microsecond)

    run =
      timed_run(
        status: "waiting_approval",
        started_at: first,
        completed_at: nil,
        wait_started_at: DateTime.add(first, 59_000, :microsecond),
        duration_ms: nil
      )

    html =
      render_trace(%{
        run
        | status: "waiting_approval",
          trace_started_at: first,
          trace_completed_at: nil,
          completed_at: nil
      })

    dom = LazyHTML.from_fragment(html)
    assert LazyHTML.query(dom, "[data-part='trace-phase-row'][data-phase='waiting']") |> Enum.count() == 1
    assert html =~ "starting 59 ms after admission"
    refute html =~ "Not recorded"
  end

  test "interruption intervals remain explicitly unobserved" do
    html = render_trace(timed_run(status: "interrupted", diagnostic: %{"kind" => "exit"}, execution_duration_ms: nil))
    assert html =~ "Unobserved interval"
    dom = LazyHTML.from_fragment(html)
    assert LazyHTML.query(dom, "[data-part='trace-phase-row'][data-phase='unknown']") |> Enum.count() == 1
    assert LazyHTML.query(dom, "[data-part='trace-segment'][data-phase='execution']") |> Enum.empty?()
  end

  test "the axis includes an attempt ending after the run's recorded terminal timestamp" do
    html = render_trace(timed_run(completed_at: ~U[2026-01-01 00:00:06.000000Z]))
    assert html =~ "6.0 s"
    assert html =~ "width: 100.0%;"
  end

  test "trace links require a valid ID, HTTP(S), a placeholder and no embedded credentials" do
    id = String.duplicate("a", 32)

    assert AutomationExecution.trace_url(id, "https://grafana.test/traces/{trace_id}") ==
             "https://grafana.test/traces/#{id}"

    for template <- [
          "javascript:{trace_id}",
          "https://user:secret@grafana.test/{trace_id}",
          "https://grafana.test/traces",
          nil
        ] do
      assert AutomationExecution.trace_url(id, template) == nil
    end

    assert AutomationExecution.trace_url("not-a-trace", "https://grafana.test/{trace_id}") == nil
  end

  defp render_trace(run), do: render_component(&AutomationExecution.execution_observability/1, run: run, events: [])

  defp timed_run(attrs \\ []) do
    first = ~U[2026-01-01 00:00:00.000000Z]
    last = ~U[2026-01-01 00:00:05.120000Z]

    attempt =
      struct!(
        %Attempt{
          id: "first",
          step_id: "review",
          status: "approved",
          started_at: first,
          completed_at: last,
          duration_ms: 5120,
          execution_duration_ms: 59
        },
        attrs
      )

    %Run{
      id: "run",
      status: "succeeded",
      inserted_at: DateTime.truncate(first, :second),
      trace_started_at: first,
      trace_completed_at: last,
      completed_at: DateTime.truncate(last, :second),
      attempts: [attempt]
    }
  end
end
