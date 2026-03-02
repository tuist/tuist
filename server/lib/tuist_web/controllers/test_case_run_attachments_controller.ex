defmodule TuistWeb.TestCaseRunAttachmentsController do
  use TuistWeb, :controller

  alias Tuist.Authorization
  alias Tuist.Projects
  alias Tuist.Storage
  alias Tuist.Tests
  alias TuistWeb.Authentication

  def download(conn, %{
        "account_handle" => account_handle,
        "project_handle" => project_handle,
        "test_case_run_id" => test_case_run_id,
        "file_name" => file_name
      }) do
    user = Authentication.current_user(conn)

    with {:ok, project} <-
           Projects.get_project_by_slug("#{account_handle}/#{project_handle}", preload: [:account]),
         :ok <- Authorization.authorize(:test_read, user, project),
         {:ok, attachment} <- Tests.get_attachment(test_case_run_id, file_name) do
      s3_object_key =
        Tests.attachment_storage_key(%{
          account_handle: account_handle,
          project_handle: project_handle,
          test_case_run_id: test_case_run_id,
          attachment_id: attachment.id,
          file_name: file_name
        })

      url =
        Storage.generate_download_url(s3_object_key, project.account, expires_in: 3600)

      conn
      |> redirect(external: url)
      |> halt()
    else
      _ ->
        conn
        |> put_status(:not_found)
        |> assign(:reason, nil)
        |> put_view(TuistWeb.ErrorHTML)
        |> render("404.html")
        |> halt()
    end
  end
end
