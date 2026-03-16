defmodule TuistWeb.BuildController do
  use TuistWeb, :controller

  alias Tuist.Authorization
  alias Tuist.Builds
  alias Tuist.Projects
  alias Tuist.Storage
  alias TuistWeb.Authentication
  alias TuistWeb.Errors.NotFoundError

  def download(conn, %{"account_handle" => account_handle, "project_handle" => project_handle, "build_run_id" => build_id}) do
    user = Authentication.current_user(conn)

    with {:ok, project} <-
           Projects.get_project_by_slug("#{account_handle}/#{project_handle}", preload: [:account]),
         :ok <- Authorization.authorize(:build_read, user, project),
         %Builds.Build{} = build <- Builds.get_build(build_id),
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
