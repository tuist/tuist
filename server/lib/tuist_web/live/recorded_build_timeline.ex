defmodule TuistWeb.RecordedBuildTimeline do
  @moduledoc """
  Lazy delivery of Gradle and Bazel timeline metadata to the shared browser hook.
  """
  import Phoenix.Component
  import Phoenix.LiveView

  alias Phoenix.LiveView.AsyncResult
  alias Tuist.Bazel
  alias Tuist.Gradle

  def assign_timeline(socket, tab, build) do
    if tab == "timeline" do
      if socket.assigns[:timeline_build_id] == build.id do
        socket
      else
        socket
        |> assign(:timeline_build_id, build.id)
        |> assign(:timeline_version, (socket.assigns[:timeline_version] || 0) + 1)
        |> assign_async(:timeline, fn -> {:ok, %{timeline: load(build)}} end, reset: true)
      end
    else
      assign(socket, :timeline_build_id, nil)
    end
  end

  def load(%Gradle.Build{} = build), do: Gradle.Timeline.load(build)
  def load(%Bazel.Invocation{} = invocation), do: Bazel.Timeline.load(invocation)

  def handle_event("load-timeline", %{"version" => version}, socket) do
    case socket.assigns do
      %{selected_tab: "timeline", timeline_version: ^version, timeline: %{ok?: true, result: %{events: _} = timeline}} ->
        summary = Map.drop(timeline, [:events, :machine_metrics])
        {:reply, %{timeline: timeline}, assign(socket, :timeline, AsyncResult.ok(summary))}

      _ ->
        {:reply, %{error: true}, socket}
    end
  end
end
