defmodule TuistWeb.QAController do
  use TuistWeb, :controller

  alias Tuist.QA
  alias Tuist.Storage
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Plugs.LoaderPlug

  plug LoaderPlug
  plug :assign_selected_qa_screenshot

  def download_screenshot(
        %{assigns: %{selected_qa_screenshot: screenshot, selected_project: selected_project}} = conn,
        %{"account_handle" => account_handle, "project_handle" => project_handle, "qa_run_id" => qa_run_id} = _params
      ) do
    object_key =
      QA.screenshot_storage_key(%{
        account_handle: account_handle,
        project_handle: project_handle,
        qa_run_id: qa_run_id,
        screenshot_id: screenshot.id
      })

    conn
    |> put_resp_content_type("image/png", nil)
    |> send_chunked(:ok)
    |> stream_object(object_key, selected_project.account)
  end

  defp stream_object(conn, object_key, account) do
    object_key
    |> Storage.stream_object(account)
    |> Enum.reduce_while(conn, fn chunk, conn ->
      case chunk(conn, chunk) do
        {:ok, conn} -> {:cont, conn}
        {:error, _reason} -> {:halt, conn}
      end
    end)
  end

  defp assign_selected_qa_screenshot(
         %{assigns: %{selected_project: project}, params: %{"qa_run_id" => qa_run_id, "screenshot_id" => screenshot_id}} =
           conn,
         _opts
       ) do
    with {:ok, qa_run} <- QA.qa_run(qa_run_id, preload: [app_build: [preview: :project]]),
         true <- qa_run.app_build.preview.project.id == project.id,
         {:ok, screenshot} <- QA.screenshot(screenshot_id, qa_run_id: qa_run_id) do
      assign(conn, :selected_qa_screenshot, screenshot)
    else
      _ ->
        raise NotFoundError, "QA screenshot not found."
    end
  end
end
