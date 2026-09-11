defmodule TuistWeb.Marketing.BazelTimelineShowcaseLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase, async: true

  import Phoenix.LiveViewTest

  alias Tuist.Bazel.Invocation
  alias Tuist.Marketing.BazelShowcase
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Marketing.BazelTimelineShowcaseLive

  test "explains that there's no timeline when no recent invocation has one", %{conn: conn} do
    stub(BazelShowcase, :timeline_invocation, fn -> {:error, :not_found} end)

    {:ok, _lv, html} = live_isolated(conn, BazelTimelineShowcaseLive)

    assert html =~ "No Bazel invocation with a timeline yet."
  end

  test "loads the build timeline for the selected invocation", %{conn: conn} do
    project = Repo.preload(ProjectsFixtures.project_fixture(), :account)

    invocation = %Invocation{
      invocation_id: "invocation-id",
      project_id: project.id,
      project_handle: project.name,
      duration_ms: 1_000,
      build_timeline_duration_ms: 1_000,
      build_timeline_span_start_ms: [0]
    }

    stub(BazelShowcase, :timeline_invocation, fn -> {:ok, %{project: project, invocation: invocation}} end)

    {:ok, _lv, html} = live_isolated(conn, BazelTimelineShowcaseLive)

    assert html =~ ~s(data-part="bazel-timeline-showcase")
    assert html =~ ~s(data-part="timeline-skeleton")
    refute html =~ "No Bazel invocation with a timeline yet."
  end
end
