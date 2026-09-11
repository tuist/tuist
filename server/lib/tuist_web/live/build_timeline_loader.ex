defmodule TuistWeb.BuildTimelineLoader do
  @moduledoc """
  Versioned, lazy metric bootstrapping for every build timeline.
  Step metadata is downloaded separately over HTTP and never retained in LiveView.
  """
  import Phoenix.Component
  import Phoenix.LiveView

  alias Tuist.Bazel
  alias Tuist.Builds
  alias Tuist.Gradle

  def assign_timeline(socket, tab, build, force \\ false) do
    identity = {build.__struct__, build.project_id, build.id}

    cond do
      tab != "timeline" ->
        socket |> cancel_async(:timeline) |> assign(:timeline_build_id, nil)

      not force and socket.assigns[:timeline_build_id] == identity ->
        socket

      true ->
        socket
        |> cancel_async(:timeline)
        |> assign(:timeline_build_id, identity)
        |> assign(:timeline_version, (socket.assigns[:timeline_version] || 0) + 1)
        |> assign_async(:timeline, fn -> {:ok, %{timeline: bootstrap(build)}} end, reset: true)
    end
  end

  def bootstrap(%Builds.Build{} = build) do
    metrics =
      Enum.map(
        build.machine_metrics,
        &Map.take(&1, [
          :offset_ms,
          :cpu_usage_percent,
          :memory_used_bytes,
          :memory_total_bytes,
          :network_bytes_in,
          :network_bytes_out,
          :disk_bytes_read,
          :disk_bytes_written
        ])
      )

    %{duration: build.duration, machine_metrics: metrics}
  end

  def bootstrap(%Gradle.Build{} = build), do: Gradle.Timeline.bootstrap(build)
  def bootstrap(%Bazel.Invocation{} = invocation), do: Bazel.Timeline.bootstrap(invocation)

  def handle_event("load-timeline", %{"version" => version}, socket) do
    case socket.assigns do
      %{selected_tab: "timeline", timeline_version: ^version, timeline: %{ok?: true, result: timeline}} ->
        {:reply, %{timeline: timeline}, socket}

      _ ->
        {:reply, %{error: true}, socket}
    end
  end
end
