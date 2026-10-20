defmodule TuistWeb.BuildTimelineLoaderTest do
  use ExUnit.Case, async: true

  alias Phoenix.LiveView.AsyncResult
  alias Phoenix.LiveView.Socket
  alias Tuist.Builds.Build
  alias TuistWeb.BuildTimelineLoader

  test "shares versioning, forced refresh and tab reentry across build systems" do
    for build <- [
          %Build{id: "same", project_id: 1},
          %Tuist.Gradle.Build{id: "same", project_id: 1},
          %Tuist.Bazel.Invocation{id: "same", project_id: 1}
        ] do
      socket = %Socket{assigns: %{__changed__: %{}}}
      overview = BuildTimelineLoader.assign_timeline(socket, "overview", build)
      refute Map.has_key?(overview.assigns, :timeline)
      opened = BuildTimelineLoader.assign_timeline(overview, "timeline", build)
      assert opened.assigns.timeline_version == 1
      assert BuildTimelineLoader.assign_timeline(opened, "timeline", build) == opened
      refreshed = BuildTimelineLoader.assign_timeline(opened, "timeline", build, true)
      assert refreshed.assigns.timeline_version == 2

      reopened =
        refreshed
        |> BuildTimelineLoader.assign_timeline("overview", build)
        |> BuildTimelineLoader.assign_timeline("timeline", build)

      assert reopened.assigns.timeline_version == 3
      changed = BuildTimelineLoader.assign_timeline(reopened, "timeline", %{build | id: "other"})
      assert changed.assigns.timeline_version == 4
    end
  end

  test "equal IDs in different build systems or projects invalidate the bootstrap" do
    socket = %Socket{assigns: %{__changed__: %{}}}
    xcode = BuildTimelineLoader.assign_timeline(socket, "timeline", %Build{id: "same", project_id: 1})
    gradle = BuildTimelineLoader.assign_timeline(xcode, "timeline", %Tuist.Gradle.Build{id: "same", project_id: 1})
    assert gradle.assigns.timeline_version == 2
    changed = BuildTimelineLoader.assign_timeline(gradle, "timeline", %Tuist.Gradle.Build{id: "same", project_id: 2})
    assert changed.assigns.timeline_version == 3
  end

  test "rejects stale and inactive-tab requests while keeping bootstrap replies repeatable" do
    payload = %{duration: 100, machine_metrics: []}

    socket = %Socket{
      assigns: %{__changed__: %{}, selected_tab: "timeline", timeline_version: 2, timeline: AsyncResult.ok(payload)}
    }

    assert {:reply, %{timeline: ^payload}, ^socket} =
             BuildTimelineLoader.handle_event("load-timeline", %{"version" => 2}, socket)

    assert {:reply, %{error: true}, ^socket} =
             BuildTimelineLoader.handle_event("load-timeline", %{"version" => 1}, socket)

    inactive = put_in(socket.assigns.selected_tab, "overview")

    assert {:reply, %{error: true}, ^inactive} =
             BuildTimelineLoader.handle_event("load-timeline", %{"version" => 2}, inactive)

    failed = put_in(socket.assigns.timeline, AsyncResult.failed(AsyncResult.loading(), :unavailable))

    assert {:reply, %{error: true}, ^failed} =
             BuildTimelineLoader.handle_event("load-timeline", %{"version" => 2}, failed)
  end

  test "Xcode bootstrap includes only metric fields and duration" do
    build = %Build{
      duration: 100,
      machine_metrics: [%{offset_ms: 0, cpu_usage_percent: 40, id: "private", build_id: "build"}]
    }

    assert BuildTimelineLoader.bootstrap(build) == %{
             duration: 100,
             machine_metrics: [%{offset_ms: 0, cpu_usage_percent: 40}]
           }
  end
end
