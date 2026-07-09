defmodule TuistWeb.API.RunnerInteractiveShellSessionController do
  use TuistWeb, :controller

  alias Tuist.Accounts
  alias Tuist.Accounts.User
  alias Tuist.Authorization
  alias Tuist.Environment
  alias Tuist.Runners.InteractiveSessions
  alias Tuist.Runners.Jobs
  alias TuistWeb.Authentication

  def create(conn, %{"job_ref" => job_ref}) when is_binary(job_ref) and job_ref != "" do
    current_user = Authentication.current_user(conn)

    with %User{} <- current_user,
         {:ok, job} <- resolve_job(job_ref),
         {:ok, account} <- Accounts.get_account_by_id(job.account_id),
         :ok <- Authorization.authorize(:runners_read, current_user, account),
         {:ok, session} <- InteractiveSessions.request_shell(job, account, current_user) do
      json(conn, %{
        session_id: session.id,
        workflow_job_id: session.workflow_job_id,
        state: Atom.to_string(session.state),
        expires_at: DateTime.to_iso8601(session.expires_at),
        websocket_url: websocket_url("/api/runners/interactive/shell/connect"),
        websocket_protocol: session.token
      })
    else
      nil ->
        conn |> put_status(:unauthorized) |> json(%{message: "You need to be authenticated to access this resource."})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{message: "The runner job was not found."})

      {:error, :unsupported_platform} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{message: "Shell access is not available for this runner platform."})

      {:error, :job_not_running} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{message: "Shell access is only available while the runner job is running."})

      {:error, :pod_unavailable} ->
        conn |> put_status(:unprocessable_entity) |> json(%{message: "The runner pod is not available for shell access."})

      _ ->
        conn
        |> put_status(:forbidden)
        |> json(%{message: "The authenticated subject is not authorized to perform this action."})
    end
  end

  def create(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{message: "A non-empty job_ref is required."})
  end

  defp resolve_job(job_ref) do
    case parse_dashboard_job_url(job_ref) do
      {:ok, account_handle, workflow_run_id, workflow_job_id} ->
        with account when not is_nil(account) <- Accounts.get_account_by_handle(account_handle),
             {:ok, %{workflow_run_id: ^workflow_run_id} = job} <- Jobs.get_for_account(account.id, workflow_job_id) do
          {:ok, job}
        else
          _ -> {:error, :not_found}
        end

      :error ->
        case Integer.parse(job_ref) do
          {workflow_job_id, ""} -> Jobs.get(workflow_job_id)
          _ -> {:error, :not_found}
        end
    end
  end

  defp parse_dashboard_job_url(job_ref) do
    path =
      case URI.parse(job_ref) do
        %URI{path: path} when is_binary(path) -> path
        _ -> job_ref
      end

    case Regex.run(~r{^/([^/]+)/runners/runs/(\d+)/jobs/(\d+)$}, path) do
      [_, account_handle, workflow_run_id, workflow_job_id] ->
        with {workflow_run_id, ""} <- Integer.parse(workflow_run_id),
             {workflow_job_id, ""} <- Integer.parse(workflow_job_id) do
          {:ok, account_handle, workflow_run_id, workflow_job_id}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp websocket_url(path) do
    uri = URI.parse(Environment.app_url(path: path, route_type: :app))
    scheme = if uri.scheme == "https", do: "wss", else: "ws"

    URI.to_string(%{uri | scheme: scheme})
  end
end
