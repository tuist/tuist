defmodule Tuist.CITest do
  use TuistTestSupport.Cases.DataCase

  alias Tuist.CI
  alias Tuist.CI.JobLog
  alias Tuist.CI.JobMetric
  alias Tuist.CI.JobStep
  alias Tuist.IngestRepo
  alias TuistTestSupport.Fixtures.CIFixtures

  describe "create_job_steps/2" do
    test "creates multiple job steps for a job run" do
      # Given
      job_run = CIFixtures.job_run_fixture()
      started_at = NaiveDateTime.utc_now()

      steps = [
        %{
          step_number: 0,
          step_name: "Set up job",
          status: "success",
          duration_ms: 3000,
          started_at: started_at
        },
        %{
          step_number: 1,
          step_name: "Set up runner",
          status: "success",
          duration_ms: 5000,
          started_at: NaiveDateTime.add(started_at, 3, :second)
        },
        %{
          step_number: 2,
          step_name: "Build",
          status: "running",
          started_at: NaiveDateTime.add(started_at, 8, :second)
        }
      ]

      # When
      {count, _} = CI.create_job_steps(job_run.id, steps)

      # Then
      assert count == 3

      inserted_steps =
        IngestRepo.all(
          from s in JobStep,
            where: s.job_run_id == ^job_run.id,
            order_by: [asc: s.step_number]
        )

      assert length(inserted_steps) == 3

      [step_0, step_1, step_2] = inserted_steps
      assert step_0.step_name == "Set up job"
      assert step_0.status == "success"
      assert step_0.duration_ms == 3000

      assert step_1.step_name == "Set up runner"
      assert step_1.step_number == 1

      assert step_2.step_name == "Build"
      assert step_2.status == "running"
      assert step_2.duration_ms == nil
    end

    test "creates job steps with optional finished_at" do
      # Given
      job_run = CIFixtures.job_run_fixture()
      started_at = NaiveDateTime.utc_now()
      finished_at = NaiveDateTime.add(started_at, 5, :second)

      steps = [
        %{
          step_number: 0,
          step_name: "Completed step",
          status: "success",
          duration_ms: 5000,
          started_at: started_at,
          finished_at: finished_at
        }
      ]

      # When
      {count, _} = CI.create_job_steps(job_run.id, steps)

      # Then
      assert count == 1

      [step] =
        IngestRepo.all(
          from s in JobStep,
            where: s.job_run_id == ^job_run.id
        )

      assert step.finished_at
    end
  end

  describe "create_job_logs/3" do
    test "creates multiple job logs for a step" do
      # Given
      job_run = CIFixtures.job_run_fixture()
      step = CIFixtures.job_step_fixture(job_run_id: job_run.id)
      timestamp = NaiveDateTime.utc_now()

      logs = [
        %{timestamp: timestamp, message: "Starting build...", stream: "stdout"},
        %{
          timestamp: NaiveDateTime.add(timestamp, 1, :second),
          message: "Compiling main.swift",
          stream: "stdout"
        },
        %{
          timestamp: NaiveDateTime.add(timestamp, 2, :second),
          message: "Warning: deprecated API",
          stream: "stderr"
        }
      ]

      # When
      {count, _} = CI.create_job_logs(step.id, job_run.id, logs)

      # Then
      assert count == 3

      inserted_logs =
        IngestRepo.all(
          from l in JobLog,
            where: l.step_id == ^step.id,
            order_by: [asc: l.timestamp]
        )

      assert length(inserted_logs) == 3

      [log_0, log_1, log_2] = inserted_logs
      assert log_0.message == "Starting build..."
      assert log_0.stream == "stdout"
      assert log_0.job_run_id == job_run.id

      assert log_1.message == "Compiling main.swift"
      assert log_2.stream == "stderr"
    end
  end

  describe "create_job_metrics/2" do
    test "creates multiple job metrics for a job run" do
      # Given
      job_run = CIFixtures.job_run_fixture()
      timestamp = NaiveDateTime.utc_now()

      metrics = [
        %{metric_type: "cpu_percent", timestamp: timestamp, value: 75.5},
        %{metric_type: "memory_percent", timestamp: timestamp, value: 45.2},
        %{metric_type: "network_bytes", timestamp: timestamp, value: 1_048_576.0},
        %{metric_type: "cpu_io_wait_percent", timestamp: timestamp, value: 5.0},
        %{metric_type: "storage_percent", timestamp: timestamp, value: 60.0}
      ]

      # When
      {count, _} = CI.create_job_metrics(job_run.id, metrics)

      # Then
      assert count == 5

      inserted_metrics =
        IngestRepo.all(
          from m in JobMetric,
            where: m.job_run_id == ^job_run.id,
            order_by: [asc: m.metric_type]
        )

      assert length(inserted_metrics) == 5

      cpu_metric = Enum.find(inserted_metrics, &(&1.metric_type == "cpu_percent"))
      assert cpu_metric.value == 75.5

      memory_metric = Enum.find(inserted_metrics, &(&1.metric_type == "memory_percent"))
      assert memory_metric.value == 45.2

      network_metric = Enum.find(inserted_metrics, &(&1.metric_type == "network_bytes"))
      assert network_metric.value == 1_048_576.0
    end

    test "creates time-series metrics data" do
      # Given
      job_run = CIFixtures.job_run_fixture()
      base_timestamp = NaiveDateTime.utc_now()

      metrics =
        Enum.flat_map(0..4, fn i ->
          timestamp = NaiveDateTime.add(base_timestamp, i * 5, :second)

          [
            %{metric_type: "cpu_percent", timestamp: timestamp, value: 50.0 + i * 10},
            %{metric_type: "memory_percent", timestamp: timestamp, value: 40.0 + i * 5}
          ]
        end)

      # When
      {count, _} = CI.create_job_metrics(job_run.id, metrics)

      # Then
      assert count == 10

      cpu_metrics =
        IngestRepo.all(
          from m in JobMetric,
            where: m.job_run_id == ^job_run.id and m.metric_type == "cpu_percent",
            order_by: [asc: m.timestamp]
        )

      assert length(cpu_metrics) == 5
      assert Enum.map(cpu_metrics, & &1.value) == [50.0, 60.0, 70.0, 80.0, 90.0]
    end
  end
end
