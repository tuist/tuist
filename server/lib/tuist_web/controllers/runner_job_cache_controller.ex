defmodule TuistWeb.RunnerJobCacheController do
  @moduledoc """
  Object storage for GitLab's `cache:` keyword, requested by a running GitLab
  job's executor with its job-scoped report token.

  Every request names GitLab Runner's object path, `project/<id>/<key>`. The
  archive's account, project and ref namespace come from the token. A token
  without a cache scope gets 404 and the job runs without a remote cache;
  storage failures are 503 so the executor retries.
  """

  use TuistWeb, :controller

  alias Tuist.Runners.GitLab.Cache
  alias Tuist.Runners.JobReports
  alias Tuist.Runners.JobReportToken

  @doc """
  `POST /api/internal/runners/jobs/cache/download`

      { "object_name": "project/123/gems", "expires_in": 3600 }
      → { "url": "..." }
  """
  def download(conn, params) do
    with {:ok, identity} <- authenticate(conn),
         {:ok, url} <- Cache.download_url(identity, params["object_name"], expires_in: params["expires_in"]) do
      json(conn, %{url: url})
    else
      error -> render_error(conn, error)
    end
  end

  @doc """
  `POST /api/internal/runners/jobs/cache/uploads`

      { "object_name": "project/123/gems" } → { "upload_id": "..." }
  """
  def start_upload(conn, params) do
    with {:ok, identity} <- authenticate(conn),
         {:ok, upload_id} <- Cache.start_upload(identity, params["object_name"]) do
      json(conn, %{upload_id: upload_id})
    else
      error -> render_error(conn, error)
    end
  end

  @doc """
  `POST /api/internal/runners/jobs/cache/uploads/part`

      { "object_name": "project/123/gems", "upload_id": "...", "part_number": 1 }
      → { "url": "..." }
  """
  def upload_part(conn, params) do
    with {:ok, identity} <- authenticate(conn),
         {:ok, url} <-
           Cache.upload_part_url(identity, params["object_name"], params["upload_id"], params["part_number"]) do
      json(conn, %{url: url})
    else
      error -> render_error(conn, error)
    end
  end

  @doc """
  `POST /api/internal/runners/jobs/cache/uploads/complete`

      {
        "object_name": "project/123/gems",
        "upload_id": "...",
        "parts": [{ "part_number": 1, "etag": "..." }]
      }
  """
  def complete_upload(conn, params) do
    with {:ok, identity} <- authenticate(conn),
         :ok <- Cache.complete_upload(identity, params["object_name"], params["upload_id"], params["parts"]) do
      send_resp(conn, :no_content, "")
    else
      error -> render_error(conn, error)
    end
  end

  @doc """
  `POST /api/internal/runners/jobs/cache/uploads/abort`

      { "object_name": "project/123/gems", "upload_id": "..." }
  """
  def abort_upload(conn, params) do
    with {:ok, identity} <- authenticate(conn),
         :ok <- Cache.abort_upload(identity, params["object_name"], params["upload_id"]) do
      send_resp(conn, :no_content, "")
    else
      error -> render_error(conn, error)
    end
  end

  # The executor only asks while a stage script is generated or run, so a
  # completed job has no use for storage.
  defp authenticate(conn) do
    with {:ok, token} <- bearer_token(conn),
         {:ok, %{workflow_job_id: workflow_job_id, provider: :gitlab} = identity} <- JobReportToken.verify(token) do
      if JobReports.running?(workflow_job_id), do: {:ok, identity}, else: {:error, :job_settled}
    else
      {:ok, _identity} -> {:error, :cache_unavailable}
      error -> error
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when token != "" -> {:ok, token}
      ["bearer " <> token] when token != "" -> {:ok, token}
      _ -> {:error, :missing_bearer}
    end
  end

  defp render_error(conn, {:error, :missing_bearer}), do: error(conn, :unauthorized, "missing bearer token")
  defp render_error(conn, {:error, :expired}), do: error(conn, :unauthorized, "report token expired")
  defp render_error(conn, {:error, :invalid}), do: error(conn, :unauthorized, "invalid report token")
  defp render_error(conn, {:error, :job_settled}), do: error(conn, :gone, "job is no longer running")
  defp render_error(conn, {:error, :invalid_object_name}), do: error(conn, :bad_request, "invalid object_name")
  defp render_error(conn, {:error, :invalid_upload}), do: error(conn, :bad_request, "invalid upload")
  defp render_error(conn, {:error, :upload_not_found}), do: error(conn, :conflict, "upload is no longer active")
  defp render_error(conn, {:error, :storage_unavailable}), do: error(conn, :service_unavailable, "storage unavailable")
  defp render_error(conn, {:error, :cache_unavailable}), do: error(conn, :not_found, "cache unavailable")

  defp error(conn, status, message), do: conn |> put_status(status) |> json(%{error: message})
end
