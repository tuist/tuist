defmodule Tuist.Runners.Workers.ExpireAPIJobWorker do
  @moduledoc """
  Runs once per API job, a day after it was created
  (`Tuist.Runners.APIJobs.create_job/2` schedules it in the same
  transaction). A job still waiting for a runner by then is cancelled, and a
  settled job's payload, which holds its secrets and clone token, is
  cleared if a lost finish report left it behind.
  """
  use Oban.Worker, queue: :default, max_attempts: 5

  alias Tuist.Runners.APIJobs

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"workflow_job_id" => workflow_job_id}}) do
    APIJobs.expire(workflow_job_id)
  end
end
