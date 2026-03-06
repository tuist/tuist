defmodule TuistWeb.BuildArchiveController do
  use TuistWeb, :controller

  alias Tuist.Authorization
  alias Tuist.Builds
  alias Tuist.Projects
  alias Tuist.Storage
  alias TuistWeb.Authentication

  def download(conn, %{"account_handle" => account_handle, "project_handle" => project_handle, "build_run_id" => build_id}) do
    user = Authentication.current_user(conn)

    with {:ok, project} <-
           Projects.get_project_by_slug("#{account_handle}/#{project_handle}", preload: [:account]),
         :ok <- Authorization.authorize(:build_read, user, project),
         %Builds.Build{} = build <- Builds.get_build(build_id),
         true <- build.project_id == project.id,
         storage_key when not is_nil(storage_key) and storage_key != "" <- build.storage_key do
      url = Storage.generate_download_url(storage_key, project.account)

      conn
      |> redirect(external: url)
      |> halt()
    else
      _ ->
        conn
        |> put_status(:not_found)
        |> text("Build archive not found")
        |> halt()
    end
  end
end
