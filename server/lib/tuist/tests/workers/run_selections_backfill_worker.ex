defmodule Tuist.Tests.Workers.RunSelectionsBackfillWorker do
  @moduledoc """
  Fills `test_run_selections` for the runs from before it existed
  (`Tuist.Tests.RunSelections.backfill/3`), as one chain of jobs: each records
  a few minutes of one project's runs and queues the next from where it
  stopped, so a single job runs at a time, on one slot of `:default`, and none
  runs long enough for Oban's lifeline to rescue it.

  The chain fills every project's last 30 days first, the period the
  dashboards open on, then goes back through their older runs. Started once by
  the migration that ships the table, and again by
  `Tuist.Release.backfill_test_run_selections/1`. A server that starts the job
  before the ClickHouse table exists fails it, and it runs again later.

  Jobs are unique by worker alone, whatever their args, so a second chain
  can't start beside a waiting one: a job queued while another waits is
  dropped, and a running job whose next one finds another waiting ends its
  chain there.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 20,
    unique: [fields: [:worker], period: :infinity, states: [:available, :scheduled, :retryable]]

  alias Tuist.Tests.RunSelections

  @recent_days 30

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_ids" => [project_id | rest], "pass" => pass} = args}) do
    cutoff = NaiveDateTime.from_iso8601!(args["cutoff"])
    window = if pass == "recent", do: [since: cutoff], else: [before: cutoff]

    case RunSelections.backfill(project_id, args["cursor"], window) do
      {:continue, cursor} ->
        continue(Map.put(args, "cursor", cursor))

      :done when rest != [] ->
        args |> Map.put("project_ids", rest) |> Map.delete("cursor") |> continue()

      :done when pass == "recent" ->
        args
        |> Map.merge(%{"project_ids" => args["all_project_ids"], "pass" => "older"})
        |> Map.delete("cursor")
        |> continue()

      :done ->
        :ok
    end
  end

  def perform(%Oban.Job{args: args}) do
    case Map.get_lazy(args, "project_ids", &RunSelections.backfill_project_ids/0) do
      [] ->
        :ok

      project_ids ->
        cutoff = NaiveDateTime.add(NaiveDateTime.utc_now(), -@recent_days * 86_400, :second)

        continue(%{
          "project_ids" => project_ids,
          "all_project_ids" => project_ids,
          "pass" => "recent",
          "cutoff" => NaiveDateTime.to_iso8601(cutoff)
        })
    end
  end

  defp continue(args) do
    {:ok, _job} = args |> new() |> Oban.insert()
    :ok
  end
end
