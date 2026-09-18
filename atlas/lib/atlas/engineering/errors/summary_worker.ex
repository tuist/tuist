defmodule Atlas.Engineering.Errors.SummaryWorker do
  @moduledoc """
  Reconciles the current error-summary reporting period, generates the LLM
  summary via `Atlas.Engineering.Errors.Agents.SummaryAgent`, persists it in
  `error_summary_runs`, and delivers it to the configured Slack channel.

  Transient LLM or Slack failures return `{:error, reason}` so Oban applies
  its backoff schedule; durable provider rejections (credit exhausted,
  invalid credentials, account suspended) are cancelled after being recorded
  on the run.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [fields: [:worker, :queue, :args], period: 60, states: :incomplete]

  alias Atlas.Audit
  alias Atlas.Engineering.Errors.Summaries
  alias Atlas.LLMs.Errors, as: LLMErrors

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    Audit.with_context(%{interface: "worker"}, fn -> do_perform(job) end)
  end

  defp do_perform(%Oban.Job{} = job) do
    scheduled_for =
      (job.inserted_at || DateTime.utc_now())
      |> DateTime.to_unix()
      |> then(&(div(&1, 60) * 60))
      |> DateTime.from_unix!()

    case Summaries.reconcile(retry?: job.attempt > 1, scheduled_for: scheduled_for) do
      {:ok, run, :delivered} ->
        Audit.record(:"error.summary.posted", %{
          target_type: "error_summary",
          target_id: run.id,
          target_label: "Error summary",
          metadata: %{
            issue_count: run.issue_count,
            path: "/engineering/errors",
            slack_channel_id: run.slack_channel_id
          }
        })

        :ok

      {:ok, _run, _outcome} ->
        :ok

      {:error, reason} ->
        handle_error(reason)
    end
  end

  defp handle_error(reason) do
    case LLMErrors.hard_failure_reason(reason) do
      nil ->
        Logger.warning("[Errors.SummaryWorker] Summary failed: #{inspect(reason)}")
        {:error, reason}

      hard_reason ->
        Logger.warning("[Errors.SummaryWorker] Model provider or Slack rejected the summary: #{hard_reason}")

        {:cancel, hard_reason}
    end
  end
end
