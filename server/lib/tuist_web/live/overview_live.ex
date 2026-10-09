defmodule TuistWeb.OverviewLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Projects.Project
  alias TuistWeb.Authorization
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.PublicOverviewCache
  alias TuistWeb.Utilities.Query

  def mount(_params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    socket =
      socket
      |> assign(
        :head_title,
        "#{dgettext("dashboard_projects", "Overview")} · #{account.name}/#{project.name} · Tuist"
      )
      |> assign(
        OpenGraph.project_image_assigns(project,
          title: dgettext("dashboard_projects", "Overview"),
          subtitle: dgettext("dashboard_projects", "Project dashboard")
        )
      )

    socket =
      if Project.xcode_project?(project) do
        TuistWeb.XcodeOverviewLive.assign_mount(socket)
      else
        socket
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

  def handle_params(_params, request_uri, %{assigns: %{selected_project: project}} = socket) do
    params = Query.query_params(request_uri)
    full_uri = URI.parse(request_uri)

    project =
      if connected?(socket) do
        Authorization.require_user_can_read_project(%{
          user: socket.assigns.current_user,
          account_handle: project.account.name,
          project_handle: project.name
        })
      else
        project
      end

    socket =
      socket
      |> assign(:selected_project, project)
      |> assign(
        :cached_public_overview,
        is_nil(socket.assigns[:current_user]) and PublicOverviewCache.public_root?(project, request_uri)
      )

    socket =
      cond do
        Project.once_project?(project) ->
          TuistWeb.OnceOverviewLive.assign_handle_params(socket, params, full_uri.path)

        Project.gradle_project?(project) ->
          TuistWeb.GradleOverviewLive.assign_handle_params(socket, params, full_uri.path)

        Project.xcode_project?(project) ->
          TuistWeb.XcodeOverviewLive.assign_handle_params(socket, params, full_uri.path)

        Project.bazel_project?(project) ->
          TuistWeb.BazelOverviewLive.assign_handle_params(socket, params, full_uri.path)

        Project.mix_project?(project) ->
          TuistWeb.MixOverviewLive.assign_handle_params(socket, params, full_uri.path)

        true ->
          socket
      end

    {:noreply, PublicOverviewCache.resolve_pending(socket)}
  end
end
