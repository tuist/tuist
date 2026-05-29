defmodule TuistWeb.RunnerJobLogsController do
  @moduledoc """
  Serves a runner job's full captured log for download.

  Once a job finishes, `Tuist.Runners.Workers.ArchiveLogsWorker` gzips
  the full log into S3 and records the object key on the job row. This
  endpoint redirects to a presigned URL for that archive — the
  GitHub-style path that keeps the download off the request servers and
  out of ClickHouse. While a job is still streaming (or before its
  archive lands), it falls back to streaming the log from ClickHouse in
  batches (`send_chunked` + `JobLogs.reduce/4`) so even a very large
  log never materialises in memory.

  Authenticated and account-scoped — a user can only download logs for a
  job in an account they can read, and the run id in the URL must match
  the job's (same gate as the detail LiveView).
  """
  use TuistWeb, :controller

  alias Tuist.Accounts
  alias Tuist.Authorization
  alias Tuist.Runners.JobLogs
  alias Tuist.Runners.Jobs
  alias Tuist.Storage
  alias TuistWeb.Authentication
  alias TuistWeb.Errors.NotFoundError

  @batch_size 2_000
  @archive_url_ttl 3_600

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
         {:ok, %{workflow_run_id: ^workflow_run_id} = job} <- Jobs.get_for_account(account.id, workflow_job_id) do
      serve(conn, account, job)
    else
      _ ->
        raise NotFoundError,
              dgettext("dashboard_runners", "The job you are looking for doesn't exist or has been moved.")
    end
  end

  # Archive is built — redirect to a presigned URL, overriding the
  # response content-disposition so the browser saves it under a
  # recognisable filename rather than the opaque object key.
  defp serve(conn, account, %{log_archive_key: key, workflow_job_id: workflow_job_id})
       when is_binary(key) and key != "" do
    url =
      Storage.generate_download_url(key, account,
        expires_in: @archive_url_ttl,
        query_params: [
          {"response-content-disposition", ~s(attachment; filename="runner-job-#{workflow_job_id}.log.gz")}
        ]
      )

    redirect(conn, external: url)
  end

  # No archive yet (still streaming, or pre-archive window) — stream the
  # log straight out of ClickHouse in batches.
  defp serve(conn, _account, %{workflow_job_id: workflow_job_id}) do
    conn =
      conn
      |> put_resp_content_type("text/plain")
      |> put_resp_header(
        "content-disposition",
        ~s(attachment; filename="runner-job-#{workflow_job_id}.log")
      )
      |> send_chunked(200)

    JobLogs.reduce(workflow_job_id, @batch_size, conn, fn lines, conn ->
      case chunk(conn, JobLogs.encode_lines(lines)) do
        {:ok, conn} -> conn
        {:error, _reason} -> conn
      end
    end)
  end
end
