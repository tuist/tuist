defmodule TuistWeb.BuildController do
  use TuistWeb, :controller

  alias Tuist.Authorization
  alias Tuist.Bazel
  alias Tuist.Builds
  alias Tuist.Builds.Trace
  alias Tuist.Gradle
  alias Tuist.Mix
  alias Tuist.Projects
  alias Tuist.Storage
  alias TuistWeb.Authentication
  alias TuistWeb.Errors.NotFoundError

  def timeline(conn, %{"account_handle" => account, "project_handle" => project_name} = params) do
    user = Authentication.current_user(conn)

    with {:ok, project} <- Projects.get_project_by_slug("#{account}/#{project_name}", preload: [:account]),
         :ok <- Authorization.authorize(:build_read, user, project),
         {:ok, build} <- Trace.get_build(project, build_id(params)),
         true <- build.project_id == project.id do
      # Bandit negotiates HTTP compression; never cache this authenticated response.
      conn
      |> put_resp_header("cache-control", "private, no-store")
      |> json(timeline_metadata(build))
    else
      _ -> raise NotFoundError, dgettext("errors", "Build not found")
    end
  end

  defp build_id(%{"build_run_id" => id}), do: id
  defp build_id(%{"invocation_id" => id}), do: id

  @doc """
  Downloads the build's timeline as a Chrome Trace Event JSON file for Perfetto.
  """
  def trace(conn, %{"account_handle" => account, "project_handle" => project_name} = params) do
    user = Authentication.current_user(conn)

    with {:ok, project} <- Projects.get_project_by_slug("#{account}/#{project_name}", preload: [:account]),
         :ok <- Authorization.authorize(:build_read, user, project),
         {:ok, build} <- Trace.get_build(project, build_id(params)),
         true <- build.project_id == project.id do
      send_trace(conn, project, build)
    else
      _ -> raise NotFoundError, dgettext("errors", "Build not found")
    end
  end

  @doc """
  Serves the same file to holders of a link signed by `Tuist.Builds.Trace.sign_token/2`,
  which the MCP server hands to agents after authorizing them for the build.
  """
  def signed_trace(conn, %{"token" => token}) do
    with {:ok, project_id, build_id} <- Trace.verify_token(token),
         {:ok, project} <- project_id |> Projects.get_project_by_id() |> ok_or_not_found(),
         {:ok, build} <- Trace.get_build(project, build_id) do
      send_trace(conn, project, build)
    else
      _ -> raise NotFoundError, dgettext("errors", "Build not found")
    end
  end

  defp ok_or_not_found(nil), do: {:error, :not_found}
  defp ok_or_not_found(project), do: {:ok, project}

  defp send_trace(conn, project, build) do
    trace =
      build
      |> Trace.load()
      |> Trace.encode(%{
        name: "#{project.account.name}/#{project.name} #{project.build_system} build",
        build_id: build.id,
        build_system: project.build_system
      })

    conn
    |> put_resp_header("cache-control", "private, no-store")
    |> send_download({:binary, JSON.encode!(trace)},
      filename: "build-#{build.id}-trace.json",
      content_type: "application/json"
    )
  end

  defp timeline_metadata(%Builds.Build{} = build), do: Builds.build_timeline(build.id, duration: build.duration)
  defp timeline_metadata(%Gradle.Build{} = build), do: Gradle.Timeline.load(build, include_metrics: false)
  defp timeline_metadata(%Mix.Build{} = build), do: Mix.Timeline.load(build, include_metrics: false)

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
