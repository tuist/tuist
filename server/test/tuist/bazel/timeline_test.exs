defmodule Tuist.Bazel.TimelineTest do
  use ExUnit.Case, async: true

  alias Tuist.Bazel.Invocation
  alias Tuist.Bazel.Timeline
  alias Tuist.Builds.RecordedSteps

  test "preserves retained overlapping intervals without inventing outcomes, targets or logs" do
    build = %Invocation{
      project_handle: "app",
      duration_ms: 5000,
      build_timeline_span_lanes: [0, 1, 2, 3],
      build_timeline_span_start_ms: [0, 100, 100, 400],
      build_timeline_span_durations_ms: [100, 200, 300, 0],
      build_timeline_span_categories: ["analysis", "execution", "execution", "execution"],
      build_timeline_span_descriptions: ["Setup", "Compile App", "Link Core", "Zero"],
      status: "failure"
    }

    timeline = Timeline.load(build)
    assert timeline.total_count == 4
    assert timeline.duration == 5000
    assert timeline.coverage == "retained_action_spans"
    assert Enum.all?(timeline.events, &(&1.status == "unknown" and &1.target == ""))
    refute timeline.has_metrics

    assert {:ok, %{steps: [%{title: "Link Core"}], pagination_metadata: %{total_count: 2}}} =
             RecordedSteps.list(build, %{start_ms: 100, end_ms: 150, page_size: 1})

    assert {:ok, %{log: nil, log_truncated: false}} = RecordedSteps.get(build, "1")
    assert {:error, :not_found} = RecordedSteps.get(%Invocation{duration_ms: 100}, "1")
  end

  test "span arrays truncate to complete rows including their lanes" do
    build = %Invocation{
      duration_ms: 100,
      build_timeline_span_lanes: [2],
      build_timeline_span_start_ms: [0, 1],
      build_timeline_span_durations_ms: [0, 1],
      build_timeline_span_categories: ["setup", "execution"],
      build_timeline_span_descriptions: ["Setup", "Incomplete"]
    }

    assert [%{lane: 2, duration_ms: 0}] = Invocation.timeline_spans(build)
    assert Invocation.timeline_spans(%{build | build_timeline_span_lanes: []}) == []
  end

  test "legacy invocations expose absent recordings without synthetic execution" do
    timeline = Timeline.load(%Invocation{duration_ms: 1200})
    assert timeline.events == []
    assert timeline.duration == 1200
    assert {:ok, %{availability: "unavailable"}} = RecordedSteps.list(%Invocation{duration_ms: 1200}, %{})
  end
end
