defmodule Tuist.Runners.Workers.CaptureGitLabIdentityWorker do
  @moduledoc """
  Captures a GitLab job's cache volume identity right after the job is acquired
  (`Tuist.Runners.CacheVolumes.Identity.capture_gitlab/1`), while its job token
  is fresh, so allocation does not have to ask GitLab.

  `Tuist.Runners.GitLab` enqueues it for every dispatched assignment, outside
  the acquisition itself, so a GitLab failure here never fails the job: without
  a captured identity, allocation resolves it live.
  """
  use Oban.Worker, queue: :webhooks, max_attempts: 3

  alias Tuist.Runners.CacheVolumes.Identity
  alias Tuist.Runners.GitLab

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"workflow_job_id" => workflow_job_id}}) do
    case GitLab.get_job(workflow_job_id) do
      %GitLab.Job{payload: payload, cache_volume_identity: nil} = job when is_binary(payload) ->
        Identity.capture_gitlab(job)
        :ok

      _ ->
        :ok
    end
  end

  def enqueue(%GitLab.Job{workflow_job_id: workflow_job_id}) do
    %{workflow_job_id: workflow_job_id} |> new() |> Oban.insert()
  end
end
