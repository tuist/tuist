defmodule TuistWeb.BuildsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Projects.Project
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Utilities.Query

  def mount(params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    socket =
      socket
      |> assign(
        :head_title,
        "#{dgettext("dashboard_builds", "Builds")} · #{account.name}/#{project.name} · Tuist"
      )
      |> assign(OpenGraph.og_image_assigns("builds"))

    socket =
      if Project.gradle_project?(project) do
        socket
        |> TuistWeb.GradleBuildsLive.assign_configuration_insights_options(params)
        |> TuistWeb.GradleBuildsLive.assign_initial_configuration_insights()
      else
        TuistWeb.XcodeBuildsLive.assign_mount(socket, params)
      end

    if connected?(socket) do
      Tuist.PubSub.subscribe("#{account.name}/#{project.name}")
    end

    {:ok, socket}
  end

  def handle_params(params, _uri, %{assigns: %{selected_project: project}} = socket) do
    if Project.gradle_project?(project) do
      {:noreply,
       socket
       |> TuistWeb.GradleBuildsLive.assign_handle_params(params)
       |> TuistWeb.GradleBuildsLive.assign_configuration_insights_options(params)
       |> TuistWeb.GradleBuildsLive.assign_configuration_insights()}
    else
      {:noreply, TuistWeb.XcodeBuildsLive.assign_handle_params(socket, params)}
    end
  end

  def handle_info(:update_configuration_insights, %{assigns: %{selected_project: project}} = socket) do
    if Project.gradle_project?(project) do
      {:noreply,
       assign(
         socket,
         :configuration_insights_analytics,
         socket.assigns.next_configuration_insights_analytics
       )}
    else
      {:noreply, TuistWeb.XcodeBuildsLive.handle_info_update_configuration_insights(socket)}
    end
  end

  def handle_info({:build_created, _build}, socket) do
    {:noreply, TuistWeb.XcodeBuildsLive.handle_info_build_created(socket)}
  end

  def handle_info({:gradle_build_created, _build}, socket) do
    if Query.has_pagination_params?(socket.assigns.uri.query) do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> TuistWeb.GradleBuildsLive.assign_handle_params(socket.assigns.current_params)
       |> TuistWeb.GradleBuildsLive.assign_configuration_insights_options(socket.assigns.current_params)
       |> TuistWeb.GradleBuildsLive.assign_initial_configuration_insights()}
    end
  end

  def handle_info(_event, socket) do
    {:noreply, socket}
  end

  def handle_event(
        "select_build_duration_type",
        %{"type" => type},
        %{assigns: %{selected_account: selected_account, selected_project: selected_project, uri: uri}} = socket
      ) do
    socket =
      push_patch(
        socket,
        to:
          "/#{selected_account.name}/#{selected_project.name}/builds?#{Query.put(uri.query, "build-duration-type", type)}",
        replace: true
      )

    {:noreply, socket}
  end

  def handle_event(
        "select_widget",
        %{"widget" => widget},
        %{assigns: %{selected_account: selected_account, selected_project: selected_project, uri: uri}} = socket
      ) do
    socket =
      push_patch(
        socket,
        to:
          "/#{selected_account.name}/#{selected_project.name}/builds?#{Query.put(uri.query, "analytics-selected-widget", widget)}",
        replace: true
      )

    {:noreply, socket}
  end

  def handle_event(
        "analytics_period_changed",
        %{"value" => %{"start" => start_date, "end" => end_date}, "preset" => preset},
        %{assigns: %{selected_account: selected_account, selected_project: selected_project}} = socket
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

    {:noreply, push_patch(socket, to: "/#{selected_account.name}/#{selected_project.name}/builds?#{query_params}")}
  end

  def handle_event(
        "configuration_insights_period_changed",
        %{"value" => %{"start" => start_date, "end" => end_date}, "preset" => preset},
        %{assigns: %{selected_account: selected_account, selected_project: selected_project}} = socket
      ) do
    query_params =
      if preset == "custom" do
        socket.assigns.uri.query
        |> Query.put("configuration-insights-date-range", "custom")
        |> Query.put("configuration-insights-start-date", start_date)
        |> Query.put("configuration-insights-end-date", end_date)
      else
        Query.put(socket.assigns.uri.query, "configuration-insights-date-range", preset)
      end

    {:noreply, push_patch(socket, to: "/#{selected_account.name}/#{selected_project.name}/builds?#{query_params}")}
  end
end
