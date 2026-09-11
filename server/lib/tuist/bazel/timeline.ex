defmodule Tuist.Bazel.Timeline do
  @moduledoc """
  Timeline metadata from Kura's bounded, retained Build Event Protocol action spans.
  No per-action outcome, log or machine sample is inferred from invocation-level data.
  """

  alias Tuist.Bazel.Invocation
  alias Tuist.Bazel.Profile

  def available?(invocation) do
    case Profile.available?(invocation) do
      nil -> Invocation.timeline_spans(invocation) != []
      available -> available
    end
  end

  def load(invocation) do
    Profile.load(invocation) || retained_summary(invocation)
  end

  def bootstrap(invocation) do
    Map.drop(Profile.load(invocation, include_steps: false) || retained_summary(invocation), [
      :events,
      :total_count,
      :target_count
    ])
  end

  def retained_summary(invocation) do
    events =
      invocation
      |> Invocation.timeline_spans()
      |> Enum.with_index()
      |> Enum.map(fn {span, index} ->
        %{
          event_id: to_string(index),
          title: span.description,
          project: invocation.project_handle,
          target: "",
          category: span.category,
          start_ms: span.start_ms,
          duration_ms: span.duration_ms,
          status: "unknown"
        }
      end)
      |> Enum.sort_by(&{&1.start_ms, &1.event_id})

    duration =
      Enum.reduce(
        events,
        max(invocation.duration_ms, invocation.build_timeline_duration_ms),
        &max(&2, &1.start_ms + &1.duration_ms)
      )

    %{
      events: events,
      total_count: length(events),
      duration: max(duration, 1),
      target_count: nil,
      has_metrics: false,
      machine_metrics: [],
      local_navigation: true,
      logs_available: false,
      time_origin: "build_start",
      coverage: "retained_action_spans"
    }
  end
end
