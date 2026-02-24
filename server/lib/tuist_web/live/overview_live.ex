defmodule TuistWeb.OverviewLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Projects.Project
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Utilities.Query

  def mount(_params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    socket =
      socket
      |> assign(
        :head_title,
        "#{dgettext("dashboard_projects", "Overview")} · #{account.name}/#{project.name} · Tuist"
      )
      |> assign(OpenGraph.og_image_assigns("overview"))

    socket =
      if Project.gradle_project?(project) do
        socket
      else
        TuistWeb.XcodeOverviewLive.assign_mount(socket)
      end

    {:ok, socket}
  end

  def handle_event(
        "analytics_period_changed",
        %{"value" => %{"start" => start_date, "end" => end_date}, "preset" => preset},
        socket
      ) do
    query_params =
      if preset == "custom" do
        socket.assigns.uri.query
        |> Query.put("analytics-date-range", "custom")
        |> Query.put("analytics-start-date", start_date)
        |> Query.put("analytics-end-date", end_date)
      else
        Query.put(socket.assigns.uri.query, "analytics-date-range", preset)
      end

    {:noreply, push_patch(socket, to: "#{socket.assigns.uri_path}?#{query_params}")}
  end

  def handle_event(
        "bundle_size_period_changed",
        %{"value" => %{"start" => start_date, "end" => end_date}, "preset" => preset},
        socket
      ) do
    query_params =
      if preset == "custom" do
        socket.assigns.uri.query
        |> Query.put("bundle-size-date-range", "custom")
        |> Query.put("bundle-size-start-date", start_date)
        |> Query.put("bundle-size-end-date", end_date)
      else
        Query.put(socket.assigns.uri.query, "bundle-size-date-range", preset)
      end

    {:noreply, push_patch(socket, to: "#{socket.assigns.uri_path}?#{query_params}")}
  end

  def handle_event(
        "builds_period_changed",
        %{"value" => %{"start" => start_date, "end" => end_date}, "preset" => preset},
        socket
      ) do
    query_params =
      if preset == "custom" do
        socket.assigns.uri.query
        |> Query.put("builds-date-range", "custom")
        |> Query.put("builds-start-date", start_date)
        |> Query.put("builds-end-date", end_date)
      else
        Query.put(socket.assigns.uri.query, "builds-date-range", preset)
      end

    {:noreply, push_patch(socket, to: "#{socket.assigns.uri_path}?#{query_params}")}
  end

  def handle_params(params, request_uri, %{assigns: %{selected_project: project}} = socket) do
    full_uri = URI.parse(request_uri)

    socket =
      if Project.gradle_project?(project) do
        TuistWeb.GradleOverviewLive.assign_handle_params(socket, params, full_uri.path)
      else
        TuistWeb.XcodeOverviewLive.assign_handle_params(socket, params, full_uri.path)
      end

    {:noreply, socket}
  end
end
