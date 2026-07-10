defmodule Tuist.Storage.Workers.ArtifactRetentionWorker do
  @moduledoc false

  alias Tuist.Environment

  @attempts_per_page 3

  def effective_retention_days(args, resource_type) do
    if Map.get(args, "self_hosted", false) do
      case Map.fetch(Environment.artifact_retention_days(), resource_type) do
        {:ok, retention_days} -> {:enabled, retention_days}
        :error -> :disabled
      end
    else
      {:enabled, Map.get(args, "retention_days")}
    end
  end

  def reschedule_with_args(%Oban.Job{} = job, args) do
    # Oban increments max_attempts when it snoozes a job. Setting it one below
    # the next page's budget gives every page three attempts, even when an
    # earlier page used one or more retries.
    max_attempts = job.attempt + @attempts_per_page - 1

    case Oban.update_job(job, %{args: args, max_attempts: max_attempts}) do
      {:ok, _job} -> {:snooze, 0}
      error -> error
    end
  end
end
