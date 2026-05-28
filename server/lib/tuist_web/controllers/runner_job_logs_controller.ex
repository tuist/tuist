defmodule TuistWeb.RunnerJobLogsController do
  @moduledoc """
  Serves a runner job's full captured log as a downloadable text file.

  Streamed in batches (`send_chunked` + `JobLogs.reduce/4`) so even a
  very large log never materialises in memory. Authenticated and
  account-scoped — a user can only download logs for a job in an
  account they can read, and the run id in the URL must match the job's
  (same gate as the detail LiveView).
  """
  use TuistWeb, :controller

  alias Tuist.Accounts
  alias Tuist.Authorization
  alias Tuist.Runners.JobLogs
  alias Tuist.Runners.Jobs
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Authentication
  alias TuistWeb.Errors.NotFoundError

  @batch_size 2_000

  def download(conn, %{
        "account_handle" => account_handle,
        "workflow_run_id" => workflow_run_id_param,
        "workflow_job_id" => workflow_job_id_param
      }) do
    account = Accounts.get_account_by_handle(account_handle)
    user = Authentication.current_user(conn)

    with false <- is_nil(account),
         :ok <- Authorization.authorize(:projects_read, user, account),
         {workflow_run_id, ""} <- Integer.parse(workflow_run_id_param),
         {workflow_job_id, ""} <- Integer.parse(workflow_job_id_param),
         {:ok, %{workflow_run_id: ^workflow_run_id}} <- Jobs.get_for_account(account.id, workflow_job_id) do
      conn =
        conn
        |> put_resp_content_type("text/plain")
        |> put_resp_header(
          "content-disposition",
          ~s(attachment; filename="runner-job-#{workflow_job_id}.log")
        )
        |> send_chunked(200)

      JobLogs.reduce(workflow_job_id, @batch_size, conn, fn lines, conn ->
        case chunk(conn, encode_lines(lines)) do
          {:ok, conn} -> conn
          {:error, _reason} -> conn
        end
      end)
    else
      _ ->
        raise NotFoundError,
              dgettext("dashboard_runners", "The job you are looking for doesn't exist or has been moved.")
    end
  end

  defp encode_lines(lines) do
    Enum.map_join(lines, "\n", fn %{ts: ts, message: message} ->
      "#{DateFormatter.format_iso(ts)} #{message}"
    end) <> "\n"
  end
end
