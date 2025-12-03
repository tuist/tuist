defmodule Tuist.CI do
  @moduledoc """
  Context module for CI-related functionality.
  """

  alias Tuist.CI.JobLog
  alias Tuist.CI.JobMetric
  alias Tuist.CI.JobRun
  alias Tuist.CI.JobStep
  alias Tuist.IngestRepo

  def list_job_runs(attrs) do
    Tuist.ClickHouseFlop.validate_and_run!(JobRun, attrs, for: JobRun)
  end

  @doc """
  Creates multiple job steps for a job run.

  ## Parameters
    - job_run_id: UUID of the parent job run
    - steps: List of step attribute maps

  ## Example
      create_job_steps(job_run_id, [
        %{step_number: 0, step_name: "Set up job", status: "success", started_at: ~U[2025-01-01 12:00:00Z]},
        %{step_number: 1, step_name: "Build", status: "running", started_at: ~U[2025-01-01 12:01:00Z]}
      ])
  """
  @spec create_job_steps(Ecto.UUID.t(), list(map())) :: {integer(), nil}
  def create_job_steps(job_run_id, steps) do
    steps_data =
      Enum.map(steps, fn step_attrs ->
        %{
          id: Map.get(step_attrs, :id, UUIDv7.generate()),
          job_run_id: job_run_id,
          step_number: step_attrs.step_number,
          step_name: step_attrs.step_name,
          status: step_attrs.status,
          duration_ms: Map.get(step_attrs, :duration_ms),
          started_at: step_attrs.started_at,
          finished_at: Map.get(step_attrs, :finished_at),
          inserted_at: Map.get(step_attrs, :inserted_at, NaiveDateTime.utc_now())
        }
      end)

    IngestRepo.insert_all(JobStep, steps_data)
  end

  @doc """
  Creates multiple job logs for a job step.

  ## Parameters
    - step_id: UUID of the parent step
    - job_run_id: UUID of the parent job run (denormalized for query efficiency)
    - logs: List of log attribute maps

  ## Example
      create_job_logs(step_id, job_run_id, [
        %{timestamp: ~U[2025-01-01 12:00:00Z], message: "Starting build...", stream: "stdout"},
        %{timestamp: ~U[2025-01-01 12:00:01Z], message: "Error: failed", stream: "stderr"}
      ])
  """
  @spec create_job_logs(Ecto.UUID.t(), Ecto.UUID.t(), list(map())) :: {integer(), nil}
  def create_job_logs(step_id, job_run_id, logs) do
    logs_data =
      Enum.map(logs, fn log_attrs ->
        %{
          id: Map.get(log_attrs, :id, UUIDv7.generate()),
          step_id: step_id,
          job_run_id: job_run_id,
          timestamp: log_attrs.timestamp,
          message: log_attrs.message,
          stream: log_attrs.stream,
          inserted_at: Map.get(log_attrs, :inserted_at, NaiveDateTime.utc_now())
        }
      end)

    IngestRepo.insert_all(JobLog, logs_data)
  end

  @doc """
  Creates multiple job metrics for a job run.

  ## Parameters
    - job_run_id: UUID of the parent job run
    - metrics: List of metric attribute maps

  ## Example
      create_job_metrics(job_run_id, [
        %{metric_type: "cpu_percent", timestamp: ~U[2025-01-01 12:00:00Z], value: 75.5},
        %{metric_type: "memory_percent", timestamp: ~U[2025-01-01 12:00:00Z], value: 45.2}
      ])
  """
  @spec create_job_metrics(Ecto.UUID.t(), list(map())) :: {integer(), nil}
  def create_job_metrics(job_run_id, metrics) do
    metrics_data =
      Enum.map(metrics, fn metric_attrs ->
        %{
          id: Map.get(metric_attrs, :id, UUIDv7.generate()),
          job_run_id: job_run_id,
          metric_type: metric_attrs.metric_type,
          timestamp: metric_attrs.timestamp,
          value: metric_attrs.value,
          inserted_at: Map.get(metric_attrs, :inserted_at, NaiveDateTime.utc_now())
        }
      end)

    IngestRepo.insert_all(JobMetric, metrics_data)
  end
end
