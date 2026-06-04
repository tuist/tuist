defmodule TuistWeb.RunnerJobLogsController do
  @moduledoc """
  Serves a runner job's full captured log for download.

  Once a job finishes, `Tuist.Runners.Workers.ArchiveLogsWorker`
  gzips the full log into S3 and stamps `log_archived_at` on the
  job row. This endpoint redirects to a presigned URL for that
  archive — the GitHub-style path that keeps the download off the
  request servers and out of ClickHouse. Until the archive lands,
  the endpoint 404s; the UI hides the download affordance during
  that window so the user never sees a button that won't work.

  Authenticated and account-scoped — a user can only download logs
  for a job in an account they can read, and the run id in the URL
  must match the job's (same gate as the detail LiveView).
  """
  use TuistWeb, :controller

  alias Tuist.Accounts
  alias Tuist.Authorization
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.Workers.ArchiveLogsWorker
  alias Tuist.Storage
  alias TuistWeb.Authentication
  alias TuistWeb.Errors.NotFoundError

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
         {:ok, %{workflow_run_id: ^workflow_run_id, log_archived_at: %DateTime{}} = job} <-
           Jobs.get_for_account(account.id, workflow_job_id) do
      serve(conn, account, job)
    else
      _ ->
        raise NotFoundError,
              dgettext("dashboard_runners", "The job you are looking for doesn't exist or has been moved.")
    end
  end

  defp serve(conn, account, %{account_id: account_id, workflow_job_id: workflow_job_id}) do
    key = ArchiveLogsWorker.archive_key(account_id, workflow_job_id)

    url =
      Storage.generate_download_url(key, account,
        expires_in: @archive_url_ttl,
        query_params: [
          {"response-content-disposition", ~s(attachment; filename="runner-job-#{workflow_job_id}.log.gz")}
        ]
      )

    redirect(conn, external: url)
  end
end
