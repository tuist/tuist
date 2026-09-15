defmodule TuistWeb.BuildController do
  use TuistWeb, :controller

  alias Tuist.Authorization
  alias Tuist.Bazel
  alias Tuist.Builds
  alias Tuist.Gradle
  alias Tuist.Projects
  alias Tuist.Storage
  alias TuistWeb.Authentication
  alias TuistWeb.Errors.NotFoundError

  def timeline(conn, %{"account_handle" => account, "project_handle" => project_name} = params) do
    user = Authentication.current_user(conn)

    with {:ok, project} <- Projects.get_project_by_slug("#{account}/#{project_name}", preload: [:account]),
         :ok <- Authorization.authorize(:build_read, user, project),
         {:ok, build} <- timeline_build(project, params),
         true <- build.project_id == project.id do
      # Bandit negotiates HTTP compression; never cache this authenticated response.
      conn
      |> put_resp_header("cache-control", "private, no-store")
      |> json(timeline_metadata(build))
    else
      _ -> raise NotFoundError, dgettext("errors", "Build not found")
    end
  end

  defp timeline_build(%{build_system: :gradle} = project, %{"build_run_id" => id}),
    do: Gradle.get_build(id, project_id: project.id)

  defp timeline_build(%{build_system: :bazel} = project, %{"invocation_id" => id}),
    do: Bazel.get_invocation(project.id, id, include_cache_summary: false)

  defp timeline_build(%{build_system: :xcode} = project, %{"build_run_id" => id}),
    do: Builds.get_build(id, project_id: project.id)

  defp timeline_build(_project, _params), do: {:error, :not_found}

  defp timeline_metadata(%Builds.Build{} = build), do: Builds.build_timeline(build.id, duration: build.duration)
  defp timeline_metadata(%Gradle.Build{} = build), do: Gradle.Timeline.load(build, include_metrics: false)
  defp timeline_metadata(%Bazel.Invocation{} = build), do: build |> Bazel.Timeline.load() |> Map.delete(:machine_metrics)

  def download(conn, %{"account_handle" => account_handle, "project_handle" => project_handle, "build_run_id" => build_id}) do
    user = Authentication.current_user(conn)

    with {:ok, project} <-
           Projects.get_project_by_slug("#{account_handle}/#{project_handle}", preload: [:account]),
         :ok <- Authorization.authorize(:build_read, user, project),
         {:ok, build} <- Builds.get_build(build_id, project_id: project.id),
         true <- build.project_id == project.id do
      storage_key = Builds.build_storage_key(account_handle, project_handle, build_id)
      url = Storage.generate_download_url(storage_key, project.account)

      conn
      |> redirect(external: url)
      |> halt()
    else
      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: dgettext("errors", "You are not authorized to access this build")})
        |> halt()

      _ ->
        raise NotFoundError, dgettext("errors", "Build not found")
    end
  end
end
