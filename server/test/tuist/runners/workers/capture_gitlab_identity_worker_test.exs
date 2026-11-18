defmodule Tuist.Runners.Workers.CaptureGitLabIdentityWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Runners.CacheVolumes.Identity
  alias Tuist.Runners.GitLab
  alias Tuist.Runners.Workers.CaptureGitLabIdentityWorker

  test "captures the identity of an assignment that still holds its payload" do
    job = %GitLab.Job{workflow_job_id: 10, payload: "{}"}
    expect(GitLab, :get_job, fn 10 -> job end)
    expect(Identity, :capture_gitlab, fn ^job -> :ok end)

    assert perform_job(CaptureGitLabIdentityWorker, %{workflow_job_id: 10}) == :ok
  end

  test "skips an assignment already captured, settled or gone" do
    for job <- [
          %GitLab.Job{workflow_job_id: 10, payload: "{}", cache_volume_identity: %{"provider" => "gitlab"}},
          %GitLab.Job{workflow_job_id: 10, payload: nil},
          nil
        ] do
      expect(GitLab, :get_job, fn 10 -> job end)
      reject(&Identity.capture_gitlab/1)

      assert perform_job(CaptureGitLabIdentityWorker, %{workflow_job_id: 10}) == :ok
    end
  end
end
