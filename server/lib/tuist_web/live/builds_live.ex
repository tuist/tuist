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
      cond do
        Project.bazel_project?(project) ->
          params
          |> TuistWeb.BazelBuildsLive.mount(%{}, socket)
          |> elem(1)

        Project.gradle_project?(project) ->
          socket
          |> TuistWeb.GradleBuildsLive.assign_configuration_insights_options(params)
          |> TuistWeb.GradleBuildsLive.assign_initial_configuration_insights()

        true ->
          TuistWeb.XcodeBuildsLive.assign_mount(socket, params)
      end

    {:ok, socket}
  end

  def handle_params(_params, uri, %{assigns: %{selected_project: project}} = socket) do
    params = Query.query_params(uri)

    cond do
      Project.bazel_project?(project) ->
        TuistWeb.BazelBuildsLive.handle_params(params, uri, socket)

      Project.gradle_project?(project) ->
        {:noreply,
         socket
         |> TuistWeb.GradleBuildsLive.assign_handle_params(params)
         |> TuistWeb.GradleBuildsLive.assign_configuration_insights_options(params)
         |> TuistWeb.GradleBuildsLive.assign_configuration_insights()}

      true ->
        {:noreply, TuistWeb.XcodeBuildsLive.assign_handle_params(socket, params)}
    end
  end

  def handle_info(_event, socket) do
    {:noreply, socket}
  end

  def handle_event("select_build_duration_type", %{"type" => type}, socket) do
    query = Query.put(socket.assigns.uri.query, "build-duration-type", type)
    uri = URI.new!("?" <> query)

    {:noreply,
     socket
     |> assign(:selected_build_duration_type, type)
     |> assign(:uri, uri)
     |> push_event("replace-url", %{url: "?" <> query})}
  end

  def handle_event("select_duration_type", params, %{assigns: %{selected_project: project}} = socket)
      when is_map(params) do
    if Project.bazel_project?(project) do
      TuistWeb.BazelBuildsLive.handle_event("select_duration_type", params, socket)
    else
      {:noreply, socket}
    end
  end

  def handle_event("add_filter", params, %{assigns: %{selected_project: project}} = socket) do
    if Project.bazel_project?(project) do
      TuistWeb.BazelBuildsLive.handle_event("add_filter", params, socket)
    else
      {:noreply, socket}
    end
  end

  def handle_event("update_filter", params, %{assigns: %{selected_project: project}} = socket) do
    if Project.bazel_project?(project) do
      TuistWeb.BazelBuildsLive.handle_event("update_filter", params, socket)
    else
      {:noreply, socket}
    end
  end

  def handle_event("select_build_duration_chart_type", %{"type" => type}, socket) do
    query = Query.put(socket.assigns.uri.query, "build-duration-chart-type", type)
    uri = URI.new!("?" <> query)
    socket = assign(socket, build_duration_chart_type: type, uri: uri)
    opts = TuistWeb.XcodeBuildsLive.analytics_opts(socket.assigns)
    group_by = TuistWeb.XcodeBuildsLive.scatter_group_by_atom(socket.assigns.build_duration_scatter_group_by)

    {:noreply,
     socket
     |> push_event("replace-url", %{url: "?" <> query})
     |> TuistWeb.XcodeBuildsLive.assign_build_duration_chart(type, group_by, opts)}
  end

  def handle_event("select_widget", %{"widget" => _widget} = params, %{assigns: %{selected_project: project}} = socket) do
    cond do
      Project.bazel_project?(project) ->
        TuistWeb.BazelBuildsLive.handle_event("select_widget", params, socket)

      Project.gradle_project?(project) ->
        TuistWeb.GradleBuildsLive.handle_event("select_widget", params, socket)

      true ->
        TuistWeb.XcodeBuildsLive.handle_event("select_widget", params, socket)
    end
  end

  def handle_event(
        "analytics_period_changed",
        %{"value" => %{"start" => start_date, "end" => end_date}, "preset" => preset},
        %{assigns: %{selected_account: selected_account, selected_project: selected_project}} = socket
      ) do
    if Project.bazel_project?(selected_project) do
      TuistWeb.BazelBuildsLive.handle_event(
        "analytics_period_changed",
        %{"value" => %{"start" => start_date, "end" => end_date}, "preset" => preset},
        socket
      )
    else
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
  end
end
