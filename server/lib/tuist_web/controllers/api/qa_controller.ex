defmodule TuistWeb.API.QAController do
  use TuistWeb, :controller

  alias Tuist.Authorization
  alias Tuist.QA
  alias TuistWeb.Authentication

  @spec create_step(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create_step(conn, %{"run_id" => run_id, "summary" => summary}) do
    with {:ok, qa_run} <- QA.qa_run(run_id),
         qa_run = Tuist.Repo.preload(qa_run, app_build: [preview: :project]),
         project = qa_run.app_build.preview.project,
         subject = Authentication.authenticated_subject(conn),
         :ok <- Authorization.authorize(:project_qa_run_step_create, subject, project),
         {:ok, qa_run_step} <-
           QA.create_qa_run_step(%{
             qa_run_id: qa_run.id,
             summary: summary
           }) do
      conn
      |> put_status(:created)
      |> json(%{
        id: qa_run_step.id,
        qa_run_id: qa_run_step.qa_run_id,
        summary: qa_run_step.summary,
        inserted_at: qa_run_step.inserted_at
      })
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "QA run not found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Forbidden"})

      {:error, changeset} ->
        errors = Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Validation failed", details: errors})
    end
  end

  def create_step(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required parameter: summary"})
  end

  @spec update_run(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def update_run(conn, %{"run_id" => run_id, "status" => status} = params) when status in ["completed", "failed"] do
    with {:ok, qa_run} <- QA.qa_run(run_id),
         qa_run = Tuist.Repo.preload(qa_run, app_build: [preview: :project]),
         project = qa_run.app_build.preview.project,
         subject = Authentication.authenticated_subject(conn),
         :ok <- Authorization.authorize(:project_qa_run_update, subject, project),
         {:ok, updated_qa_run} <- QA.update_qa_run(qa_run, %{status: status, summary: Map.get(params, "summary")}) do
      conn
      |> put_status(:ok)
      |> json(%{
        id: updated_qa_run.id,
        status: updated_qa_run.status,
        summary: updated_qa_run.summary,
        updated_at: updated_qa_run.updated_at
      })
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "QA run not found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Forbidden"})

      {:error, changeset} ->
        errors = Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Validation failed", details: errors})
    end
  end

  def update_run(conn, %{"status" => status}) when status not in ["completed", "failed"] do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Invalid status. Only 'completed' and 'failed' are allowed."})
  end

  def update_run(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required parameter: status"})
  end
end
