defmodule TuistWeb.Marketing.BazelTimelineShowcaseLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase, async: true

  import Phoenix.LiveViewTest

  alias Tuist.Bazel.Invocation
  alias Tuist.Bazel.Timeline
  alias Tuist.Marketing.BazelShowcase
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Marketing.BazelTimelineShowcaseLive

  test "explains that there's no timeline when no recent invocation has one", %{conn: conn} do
    stub(BazelShowcase, :timeline_invocation, fn -> {:error, :not_found} end)

    {:ok, _lv, html} = live_isolated(conn, BazelTimelineShowcaseLive)

    assert html =~ "No Bazel invocation with a timeline yet."
  end

  test "renders the cached timeline and downloads its steps from the showcase", %{conn: conn} do
    project = Repo.preload(ProjectsFixtures.project_fixture(visibility: :public), :account)

    invocation = %Invocation{
      invocation_id: "invocation-id",
      project_id: project.id,
      project_handle: project.name,
      duration_ms: 1_000,
      build_timeline_duration_ms: 1_000,
      build_timeline_span_lanes: [0],
      build_timeline_span_start_ms: [0],
      build_timeline_span_durations_ms: [400],
      build_timeline_span_categories: ["execution"],
      build_timeline_span_descriptions: ["Rustc //app:lib"]
    }

    timeline = invocation |> Timeline.retained_summary() |> Map.drop([:events, :total_count, :target_count])

    stub(BazelShowcase, :timeline_invocation, fn ->
      {:ok, %{project: project, invocation: invocation, timeline: timeline}}
    end)

    {:ok, lv, html} = live_isolated(conn, BazelTimelineShowcaseLive)

    refute html =~ "No Bazel invocation with a timeline yet."
    assert has_element?(lv, ~s(#build-timeline[data-url="/blog/bazel/timeline.json?invocation_id=invocation-id"]))

    render_hook(lv, "load-timeline", %{"version" => 1})
    assert_reply lv, %{timeline: %{coverage: "retained_action_spans"}}
  end
end
