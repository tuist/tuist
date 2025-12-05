defmodule TuistTestSupport.Fixtures.CIFixtures do
  @moduledoc """
  Fixtures for CI entities.
  """
  alias Tuist.CI
  alias Tuist.CI.JobLog
  alias Tuist.CI.JobMetric
  alias Tuist.CI.JobRun
  alias Tuist.CI.JobStep
  alias Tuist.IngestRepo
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  def job_run_fixture(attrs \\ []) do
    project_id =
      Keyword.get_lazy(attrs, :project_id, fn ->
        ProjectsFixtures.project_fixture().id
      end)

    id = Keyword.get(attrs, :id, UUIDv7.generate())

    job_run_data = %{
      id: id,
      project_id: project_id,
      workflow_id: Keyword.get(attrs, :workflow_id, "workflow-#{:rand.uniform(1000)}"),
      workflow_name: Keyword.get(attrs, :workflow_name, "Test Workflow"),
      job_id: Keyword.get(attrs, :job_id, "job-#{:rand.uniform(1000)}"),
      job_name: Keyword.get(attrs, :job_name, "Test Job"),
      git_branch: Keyword.get(attrs, :git_branch, "main"),
      git_commit_sha: Keyword.get(attrs, :git_commit_sha, "abc123def456"),
      git_ref: Keyword.get(attrs, :git_ref),
      runner_machine: Keyword.get(attrs, :runner_machine, "mac/silicon"),
      runner_configuration: Keyword.get(attrs, :runner_configuration, "4 CPU / 16 GB RAM"),
      status: Keyword.get(attrs, :status, "success"),
      duration_ms: Keyword.get(attrs, :duration_ms, 5000),
      started_at: Keyword.get(attrs, :started_at, NaiveDateTime.utc_now()),
      inserted_at: Keyword.get(attrs, :inserted_at, NaiveDateTime.utc_now())
    }

    IngestRepo.insert_all(JobRun, [job_run_data])

    %{
      id: id,
      project_id: project_id,
      workflow_id: job_run_data.workflow_id,
      workflow_name: job_run_data.workflow_name,
      job_id: job_run_data.job_id,
      job_name: job_run_data.job_name,
      git_branch: job_run_data.git_branch,
      git_commit_sha: job_run_data.git_commit_sha,
      runner_machine: job_run_data.runner_machine,
      runner_configuration: job_run_data.runner_configuration,
      status: job_run_data.status,
      duration_ms: job_run_data.duration_ms,
      started_at: job_run_data.started_at
    }
  end

  def job_step_fixture(attrs \\ []) do
    job_run_id =
      Keyword.get_lazy(attrs, :job_run_id, fn ->
        job_run_fixture().id
      end)

    id = Keyword.get(attrs, :id, UUIDv7.generate())

    step_data = %{
      id: id,
      job_run_id: job_run_id,
      step_number: Keyword.get(attrs, :step_number, 0),
      step_name: Keyword.get(attrs, :step_name, "Test Step"),
      status: Keyword.get(attrs, :status, "success"),
      duration_ms: Keyword.get(attrs, :duration_ms, 1000),
      started_at: Keyword.get(attrs, :started_at, NaiveDateTime.utc_now()),
      finished_at: Keyword.get(attrs, :finished_at),
      inserted_at: Keyword.get(attrs, :inserted_at, NaiveDateTime.utc_now())
    }

    IngestRepo.insert_all(JobStep, [step_data])

    %{
      id: id,
      job_run_id: job_run_id,
      step_number: step_data.step_number,
      step_name: step_data.step_name,
      status: step_data.status,
      duration_ms: step_data.duration_ms,
      started_at: step_data.started_at,
      finished_at: step_data.finished_at
    }
  end

  def job_log_fixture(attrs \\ []) do
    job_run_id =
      Keyword.get_lazy(attrs, :job_run_id, fn ->
        job_run_fixture().id
      end)

    step_id =
      Keyword.get_lazy(attrs, :step_id, fn ->
        job_step_fixture(job_run_id: job_run_id).id
      end)

    id = Keyword.get(attrs, :id, UUIDv7.generate())

    log_data = %{
      id: id,
      step_id: step_id,
      job_run_id: job_run_id,
      timestamp: Keyword.get(attrs, :timestamp, NaiveDateTime.utc_now()),
      message: Keyword.get(attrs, :message, "Test log message"),
      stream: Keyword.get(attrs, :stream, "stdout"),
      inserted_at: Keyword.get(attrs, :inserted_at, NaiveDateTime.utc_now())
    }

    IngestRepo.insert_all(JobLog, [log_data])

    %{
      id: id,
      step_id: step_id,
      job_run_id: job_run_id,
      timestamp: log_data.timestamp,
      message: log_data.message,
      stream: log_data.stream
    }
  end

  def job_metric_fixture(attrs \\ []) do
    job_run_id =
      Keyword.get_lazy(attrs, :job_run_id, fn ->
        job_run_fixture().id
      end)

    id = Keyword.get(attrs, :id, UUIDv7.generate())

    metric_data = %{
      id: id,
      job_run_id: job_run_id,
      metric_type: Keyword.get(attrs, :metric_type, "cpu_percent"),
      timestamp: Keyword.get(attrs, :timestamp, NaiveDateTime.utc_now()),
      value: Keyword.get(attrs, :value, 50.0),
      inserted_at: Keyword.get(attrs, :inserted_at, NaiveDateTime.utc_now())
    }

    IngestRepo.insert_all(JobMetric, [metric_data])

    %{
      id: id,
      job_run_id: job_run_id,
      metric_type: metric_data.metric_type,
      timestamp: metric_data.timestamp,
      value: metric_data.value
    }
  end

  def create_job_steps_fixture(job_run_id, steps) do
    CI.create_job_steps(job_run_id, steps)
  end

  def create_job_logs_fixture(step_id, job_run_id, logs) do
    CI.create_job_logs(step_id, job_run_id, logs)
  end

  def create_job_metrics_fixture(job_run_id, metrics) do
    CI.create_job_metrics(job_run_id, metrics)
  end
end
