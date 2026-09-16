defmodule TuistWeb.RunnerJobCacheControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Repo
  alias Tuist.Runners.Buildkite
  alias Tuist.Runners.Buildkite.ReportToken
  alias Tuist.Runners.GitLab
  alias Tuist.Runners.JobReportToken
  alias Tuist.Runners.WorkflowJob
  alias Tuist.Storage

  setup do
    %{account: account} = organization_fixture(preload: [:account])

    job =
      Repo.insert!(%GitLab.Job{
        account_id: account.id,
        url: "https://gitlab.com",
        job_id: 42,
        project_path: "acme/mobile",
        pipeline_id: 90
      })

    payload = %{"job_info" => %{"project_id" => 123}, "git_info" => %{"protected" => true}}

    %{
      account: account,
      job: job,
      token: JobReportToken.mint(job, payload),
      key: "runner-gitlab-cache/#{account.name}/123/protected/gems"
    }
  end

  defp authed(conn, token), do: put_req_header(conn, "authorization", "Bearer #{token}")

  test "downloads through a presigned URL for the token's scope", %{conn: conn, token: token, key: key} do
    expect(Storage, :generate_download_url, fn ^key, _account, opts ->
      assert opts[:expires_in] == 600
      "https://storage.example.com/#{key}?signature=get"
    end)

    conn =
      conn
      |> authed(token)
      |> post("/api/internal/runners/jobs/cache/download", %{"object_name" => "project/123/gems", "expires_in" => 600})

    assert json_response(conn, 200) == %{"url" => "https://storage.example.com/#{key}?signature=get"}
  end

  test "uploads in parts", %{conn: conn, token: token, key: key} do
    expect(Storage, :multipart_start, fn ^key, _account -> {:ok, "upload-1"} end)

    expect(Storage, :multipart_generate_url, fn ^key, "upload-1", 1, _account, _opts ->
      "https://storage.example.com/part"
    end)

    expect(Storage, :multipart_complete_upload, fn ^key, "upload-1", [{1, "etag-1"}], _account -> :ok end)

    started =
      conn
      |> authed(token)
      |> post("/api/internal/runners/jobs/cache/uploads", %{"object_name" => "project/123/gems"})

    assert json_response(started, 200) == %{"upload_id" => "upload-1"}

    part =
      build_conn()
      |> authed(token)
      |> post("/api/internal/runners/jobs/cache/uploads/part", %{
        "object_name" => "project/123/gems",
        "upload_id" => "upload-1",
        "part_number" => 1
      })

    assert json_response(part, 200) == %{"url" => "https://storage.example.com/part"}

    completed =
      build_conn()
      |> authed(token)
      |> post("/api/internal/runners/jobs/cache/uploads/complete", %{
        "object_name" => "project/123/gems",
        "upload_id" => "upload-1",
        "parts" => [%{"part_number" => 1, "etag" => "etag-1"}]
      })

    assert response(completed, 204)
  end

  test "aborts an upload", %{conn: conn, token: token, key: key} do
    expect(Storage, :multipart_abort, fn ^key, "upload-1", _account -> :ok end)

    conn =
      conn
      |> authed(token)
      |> post("/api/internal/runners/jobs/cache/uploads/abort", %{
        "object_name" => "project/123/gems",
        "upload_id" => "upload-1"
      })

    assert response(conn, 204)
  end

  test "maps failures to statuses the executor acts on", %{conn: conn, token: token} do
    stub(Storage, :multipart_start, fn _, _ -> {:error, :timeout} end)
    stub(Storage, :multipart_complete_upload, fn _, _, _, _ -> {:error, :multipart_upload_not_found} end)

    unavailable =
      conn |> authed(token) |> post("/api/internal/runners/jobs/cache/uploads", %{"object_name" => "project/123/gems"})

    assert json_response(unavailable, 503)["error"] == "storage unavailable"

    other_project =
      build_conn()
      |> authed(token)
      |> post("/api/internal/runners/jobs/cache/uploads", %{"object_name" => "project/9/gems"})

    assert json_response(other_project, 400)["error"] == "invalid object_name"

    bad_part =
      build_conn()
      |> authed(token)
      |> post("/api/internal/runners/jobs/cache/uploads/part", %{
        "object_name" => "project/123/gems",
        "upload_id" => "upload-1",
        "part_number" => 0
      })

    assert json_response(bad_part, 400)["error"] == "invalid upload"

    gone =
      build_conn()
      |> authed(token)
      |> post("/api/internal/runners/jobs/cache/uploads/complete", %{
        "object_name" => "project/123/gems",
        "upload_id" => "upload-1",
        "parts" => [%{"part_number" => 1, "etag" => "etag-1"}]
      })

    assert json_response(gone, 409)["error"] == "upload is no longer active"
  end

  test "a token minted without a cache scope runs without a remote cache", %{conn: conn, job: job} do
    reject(&Storage.generate_download_url/3)

    conn =
      conn
      |> authed(JobReportToken.mint(job))
      |> post("/api/internal/runners/jobs/cache/download", %{"object_name" => "project/123/gems"})

    assert json_response(conn, 404)["error"] == "cache unavailable"
  end

  test "a Buildkite token cannot use GitLab cache storage", %{conn: conn, account: account} do
    reject(&Storage.multipart_start/2)

    {:ok, buildkite_job} =
      %Buildkite.Job{}
      |> Buildkite.Job.changeset(%{
        job_uuid: Ecto.UUID.generate(),
        account_id: account.id,
        organization_slug: "acme",
        pipeline_slug: "ios"
      })
      |> Repo.insert(returning: true)

    token = ReportToken.mint(%{workflow_job_id: buildkite_job.workflow_job_id, account_id: account.id})

    conn =
      conn |> authed(token) |> post("/api/internal/runners/jobs/cache/uploads", %{"object_name" => "project/123/gems"})

    assert json_response(conn, 404)["error"] == "cache unavailable"
  end

  test "a completed job cannot use cache storage", %{conn: conn, account: account, job: job, token: token} do
    reject(&Storage.generate_download_url/3)
    now = DateTime.utc_now()

    Repo.insert!(%WorkflowJob{
      workflow_job_id: job.workflow_job_id,
      account_id: account.id,
      provider: "gitlab",
      status: "completed",
      fleet_name: "linux-amd64",
      enqueued_at: now,
      completed_at: now
    })

    conn =
      conn |> authed(token) |> post("/api/internal/runners/jobs/cache/download", %{"object_name" => "project/123/gems"})

    assert json_response(conn, 410)["error"] == "job is no longer running"
  end

  test "requires a report token", %{conn: conn} do
    conn = post(conn, "/api/internal/runners/jobs/cache/download", %{"object_name" => "project/123/gems"})
    assert json_response(conn, 401)["error"] == "missing bearer token"
  end
end
