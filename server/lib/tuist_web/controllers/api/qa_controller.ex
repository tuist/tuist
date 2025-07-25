defmodule TuistWeb.API.QAController do
  use TuistWeb, :controller
  
  alias Tuist.Authorization
  alias Tuist.QA
  alias TuistWeb.Authentication

  @spec create_step(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create_step(conn, %{"run_id" => run_id, "summary" => summary}) do
    with {:ok, qa_run} <- QA.get_qa_run(run_id),
         qa_run = Tuist.Repo.preload(qa_run, app_build: [preview: :project]),
         project = qa_run.app_build.preview.project,
         subject = Authentication.authenticated_subject(conn),
         :ok <- Authorization.authorize(:project_qa_run_create, subject, project),
         {:ok, qa_run_step} <- QA.create_qa_run_step(%{
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
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Validation failed", details: changeset})
    end
  end
  
  def create_step(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required parameter: summary"})
  end
end