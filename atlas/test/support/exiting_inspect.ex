defmodule Atlas.TestSupport.ExitingInspect do
  @moduledoc """
  A term that exits when it is inspected.

  `Atlas.Agents.Sessions.TelemetryHandler` falls back to `inspect/1` for
  telemetry metadata it has no encoding for, so putting this in a payload is a
  deterministic way to make the handler exit rather than raise, which is what a
  connection that has gone away or a call that times out looks like from the
  handler's side.

  It lives here rather than in the test file because `Inspect` is a consolidated
  protocol: only implementations compiled alongside the project are folded into
  it, and test files are compiled after consolidation has already run.
  """

  defstruct reason: :no_connection
end

defimpl Inspect, for: Atlas.TestSupport.ExitingInspect do
  def inspect(term, _opts), do: exit(term.reason)
end
