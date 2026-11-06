defmodule TuistWeb.Helpers.RunnerJobDurations do
  @moduledoc """
  Durations shown for a runner job on the job page, the CI context card,
  and the job lists.

  Only a job that is still in the matching phase gets a live value
  (now minus the phase's start). A terminal job (`completed` or
  `cancelled`) is measured between its recorded timestamps, and a phase
  it never reached, such as the claim of a job GitHub skipped or
  cancelled before a runner picked it up, measures as 0.
  """
  alias Tuist.Utilities.DateFormatter

  @doc """
  Time the job waited for a runner: live while `queued`, `claimed_at -
  enqueued_at` once claimed, and 0 for a job that was never claimed.
  """
  def queued_ms(%{status: "queued", enqueued_at: enqueued}), do: DateFormatter.ms_since(enqueued)

  def queued_ms(%{enqueued_at: %DateTime{} = enqueued, claimed_at: %DateTime{} = claimed}),
    do: elapsed_ms(enqueued, claimed)

  def queued_ms(_), do: 0

  @doc """
  Time the runner executed the job: live while `running`,
  `completed_at - started_at` once finished, and 0 for a job that never
  started.
  """
  def run_ms(%{status: "running", started_at: started}), do: DateFormatter.ms_since(started)

  def run_ms(%{started_at: %DateTime{} = started, completed_at: %DateTime{} = completed}),
    do: elapsed_ms(started, completed)

  def run_ms(_), do: 0

  @doc """
  The most informative duration for a job list row: the queue wait while
  `queued`, the time since the claim while `claimed`, and the run time
  otherwise.
  """
  def list_ms(%{status: "claimed", claimed_at: claimed}), do: DateFormatter.ms_since(claimed)
  def list_ms(%{status: "queued"} = job), do: queued_ms(job)
  def list_ms(job), do: run_ms(job)

  defp elapsed_ms(from, to), do: max(DateTime.diff(to, from, :millisecond), 0)
end
