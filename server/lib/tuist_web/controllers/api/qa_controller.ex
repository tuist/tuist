defmodule TuistWeb.API.QAController do
  use TuistWeb, :controller

  alias Tuist.QA
  alias Tuist.Storage
  alias TuistWeb.API.Authorization.AuthorizationPlug
  alias TuistWeb.Plugs.LoaderPlug

  plug LoaderPlug
  plug :load_qa_run
  plug AuthorizationPlug, :qa_step when action in [:create_step]
  plug AuthorizationPlug, :qa_run when action in [:update_run]
  plug AuthorizationPlug, :qa_screenshot when action in [:screenshot_upload, :create_screenshot]

  defp load_qa_run(%{assigns: %{selected_project: project}} = conn, _opts) do
    case conn.path_params do
      %{"qa_run_id" => run_id} ->
        case QA.qa_run(run_id, preload: [app_build: [preview: :project]]) do
          {:ok, qa_run} ->
            if qa_run.app_build.preview.project.id == project.id do
              assign(conn, :selected_qa_run, qa_run)
            else
              conn
              |> put_status(:not_found)
              |> json(%{error: "QA run not found"})
              |> halt()
            end

          {:error, :not_found} ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "QA run not found"})
            |> halt()
        end

      _ ->
        conn
    end
  end

  def create_step(conn, %{"summary" => summary, "description" => description, "issues" => issues}) do
    %{selected_qa_run: qa_run} = conn.assigns

    case QA.create_qa_step(%{
           qa_run_id: qa_run.id,
           summary: summary,
           description: description,
           issues: issues
         }) do
      {:ok, qa_step} ->
        QA.update_screenshots_with_step_id(qa_run.id, qa_step.id)

        conn
        |> put_status(:created)
        |> json(%{
          id: qa_step.id,
          qa_run_id: qa_step.qa_run_id,
          summary: qa_step.summary,
          description: qa_step.description,
          issues: qa_step.issues,
          inserted_at: qa_step.inserted_at
        })

      {:error, changeset} ->
        message =
          changeset
          |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
          |> Enum.flat_map(fn {_key, value} -> value end)
          |> Enum.join(", ")

        conn
        |> put_status(:bad_request)
        |> json(%{
          message: "QA step #{message}"
        })
    end
  end

  def update_run(%{assigns: %{selected_qa_run: qa_run}} = conn, %{"status" => status} = params) do
    case QA.update_qa_run(qa_run, %{status: status, summary: Map.get(params, "summary")}) do
      {:ok, updated_qa_run} ->
        conn
        |> put_status(:ok)
        |> json(%{
          id: updated_qa_run.id,
          status: updated_qa_run.status,
          summary: updated_qa_run.summary,
          updated_at: updated_qa_run.updated_at
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          error: "Validation failed",
          details: Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
        })
    end
  end

  def screenshot_upload(conn, %{"qa_run_id" => run_id, "file_name" => file_name}) do
    %{selected_project: project} = conn.assigns
    expires_in = 3600

    storage_key =
      QA.screenshot_storage_key(%{
        account_handle: project.account.name,
        project_handle: project.name,
        qa_run_id: run_id,
        file_name: file_name
      })

    upload_url = Storage.generate_upload_url(storage_key, expires_in: expires_in)

    conn
    |> put_status(:ok)
    |> json(%{
      url: upload_url,
      expires_at: System.system_time(:second) + expires_in
    })
  end

  def create_screenshot(%{assigns: %{selected_qa_run: qa_run}} = conn, %{"file_name" => file_name, "title" => title}) do
    case QA.create_qa_screenshot(%{
           qa_run_id: qa_run.id,
           file_name: file_name,
           title: title
         }) do
      {:ok, screenshot} ->
        conn
        |> put_status(:created)
        |> json(%{
          id: screenshot.id,
          qa_run_id: screenshot.qa_run_id,
          qa_step_id: screenshot.qa_step_id,
          file_name: screenshot.file_name,
          title: screenshot.title,
          inserted_at: screenshot.inserted_at
        })

      {:error, changeset} ->
        message =
          changeset
          |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
          |> Enum.flat_map(fn {_key, value} -> value end)
          |> Enum.join(", ")

        conn
        |> put_status(:bad_request)
        |> json(%{
          message: "QA screenshot #{message}"
        })
    end
  end
end
