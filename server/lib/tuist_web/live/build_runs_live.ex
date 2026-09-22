defmodule TuistWeb.BuildRunsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Projects
  alias Tuist.Projects.Project
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Utilities.Query

  def mount(params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    slug = Projects.get_project_slug_from_id(project.id)

    socket =
      socket
      |> assign(:head_title, "#{dgettext("dashboard_builds", "Build Runs")} · #{slug} · Tuist")
      |> assign(OpenGraph.og_image_assigns("build-runs"))

    socket =
      cond do
        Project.bazel_project?(project) ->
          params
          |> TuistWeb.BazelBuildRunsLive.mount(%{}, socket)
          |> elem(1)

        Project.gradle_project?(project) ->
          TuistWeb.GradleBuildRunsLive.assign_mount(socket)

        true ->
          TuistWeb.XcodeBuildRunsLive.assign_mount(socket)
      end

    if connected?(socket) do
      Tuist.PubSub.subscribe("#{account.name}/#{project.name}")
    end

    {:ok, socket}
  end

  def handle_params(_params, uri, %{assigns: %{selected_project: project}} = socket) do
    params = Query.query_params(uri)

    cond do
      Project.bazel_project?(project) ->
        TuistWeb.BazelBuildRunsLive.handle_params(params, uri, socket)

      Project.gradle_project?(project) ->
        {:noreply, TuistWeb.GradleBuildRunsLive.assign_handle_params(socket, params)}

      true ->
        {:noreply, TuistWeb.XcodeBuildRunsLive.assign_handle_params(socket, params)}
    end
  end

  def handle_info({:xcode_build_created, _build}, socket) do
    {:noreply, TuistWeb.XcodeBuildRunsLive.handle_info_build_created(socket)}
  end

  def handle_info({:gradle_build_created, _build}, socket) do
    {:noreply, TuistWeb.GradleBuildRunsLive.assign_handle_params(socket, socket.assigns.current_params)}
  end

  def handle_info(_event, socket) do
    {:noreply, socket}
  end

  def handle_event("add_filter", %{"value" => filter_id}, %{assigns: %{selected_project: project}} = socket) do
    cond do
      Project.bazel_project?(project) ->
        TuistWeb.BazelBuildRunsLive.handle_event("add_filter", %{"value" => filter_id}, socket)

      Project.gradle_project?(project) ->
        {:noreply, TuistWeb.GradleBuildRunsLive.handle_event_add_filter(filter_id, socket)}

      true ->
        {:noreply, TuistWeb.XcodeBuildRunsLive.handle_event_add_filter(filter_id, socket)}
    end
  end

  def handle_event("update_filter", params, %{assigns: %{selected_project: project}} = socket) do
    cond do
      Project.bazel_project?(project) ->
        TuistWeb.BazelBuildRunsLive.handle_event("update_filter", params, socket)

      Project.gradle_project?(project) ->
        {:noreply, TuistWeb.GradleBuildRunsLive.handle_event_update_filter(params, socket)}

      true ->
        {:noreply, TuistWeb.XcodeBuildRunsLive.handle_event_update_filter(params, socket)}
    end
  end

  def handle_event("search-build-runs", %{"search" => search}, socket) do
    {:noreply, TuistWeb.GradleBuildRunsLive.handle_event_search(search, socket)}
  end
end
