defmodule TuistWeb.Marketing.BazelTimelineShowcaseLive do
  @moduledoc """
  Embeds the dashboard's build timeline for a recent Bazel invocation in the
  Bazel announcement post. It runs as its own LiveView so the timeline hook's
  events reach a process that holds the invocation, the same way they reach
  the invocation page in the dashboard. Unlike the dashboard, the timeline and
  its steps come from the showcase cache, so a visit doesn't read the trace
  profile.
  """
  # Mounted as a nested LiveView inside the blog post, so it can't use
  # `TuistWeb, :live_view`: its timezone hook reads connect params, which only
  # the root LiveView may do.
  use Phoenix.LiveView

  use Phoenix.VerifiedRoutes,
    endpoint: TuistWeb.Endpoint,
    router: TuistWeb.Router,
    statics: TuistWeb.static_paths()

  import TuistWeb.Components.BuildTimeline

  alias Phoenix.LiveView.AsyncResult
  alias Tuist.Builds.RecordedSteps
  alias Tuist.Marketing.BazelShowcase
  alias TuistWeb.BuildTimelineLoader

  def mount(_params, _session, socket) do
    socket = assign(socket, :selected_tab, "timeline")

    case BazelShowcase.timeline_invocation() do
      {:ok, %{invocation: invocation, timeline: timeline}} ->
        {:ok,
         socket
         |> assign(:invocation, invocation)
         |> assign(:timeline_version, 1)
         |> assign(:timeline, AsyncResult.ok(timeline))}

      _ ->
        {:ok, assign(socket, :invocation, nil)}
    end
  end

  def render(assigns) do
    ~H"""
    <style :type={TuistWeb.ColocatedCSS}>
      [data-part="bazel-timeline-showcase"] {
        margin: var(--noora-spacing-7) 0;

        /* The dashboard sizes the viewport for hundreds of lanes; the few
           lanes of an embedded invocation leave most of that empty. */
        & .tuist-build-timeline {
          --timeline-viewport-height: 240px;
        }

        & [data-part="timeline-coverage"] {
          margin: 0 0 var(--noora-spacing-6);
          color: var(--noora-surface-label-secondary);
          font: var(--noora-font-weight-regular) var(--noora-font-body-small);
        }

        & [data-part="empty"] {
          margin: 0;
          color: var(--noora-surface-label-secondary);
          font: var(--noora-font-weight-medium) var(--noora-font-body-small);
        }
      }
    </style>

    <div data-part="bazel-timeline-showcase">
      <%= if @invocation do %>
        <.build_timeline_section
          timeline={@timeline}
          duration={@invocation.duration_ms}
          version={@timeline_version}
          source="bazel"
          url={~p"/blog/bazel/timeline.json?#{[invocation_id: @invocation.invocation_id]}"}
        />
      <% else %>
        <p data-part="empty">No Bazel invocation with a timeline yet.</p>
      <% end %>
    </div>
    """
  end

  def handle_event("load-timeline", params, socket), do: BuildTimelineLoader.handle_event("load-timeline", params, socket)

  def handle_event("load-timeline-log", %{"event_id" => id, "request_id" => request}, socket)
      when is_binary(id) and byte_size(id) <= 128 and is_integer(request) and request >= 0 do
    with %{} = invocation <- socket.assigns.invocation,
         {:ok, step} <- RecordedSteps.get(invocation, id) do
      {:noreply, push_event(socket, "timeline-log", %{request_id: request, log: Map.take(step, [:log, :log_truncated])})}
    else
      _ -> {:reply, %{error: true}, socket}
    end
  end

  def handle_event("load-timeline-log", _params, socket), do: {:reply, %{error: true}, socket}
  def handle_event("load-timeline-step", _params, socket), do: {:reply, %{error: true}, socket}
end
