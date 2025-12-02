defmodule Tuist.Runners.Workers.CleanupRunnerWorkerTest do
  use TuistTestSupport.Cases.DataCase
  use Mimic

  alias Tuist.Runners
  alias Tuist.Runners.Workers.CleanupRunnerWorker
  alias Tuist.SSHClient
  alias TuistTestSupport.Fixtures.RunnersFixtures

  describe "perform/1" do
    test "returns error when job is not found" do
      non_existent_id = UUIDv7.generate()

      result =
        CleanupRunnerWorker.perform(%Oban.Job{
          args: %{"job_id" => non_existent_id},
          attempt: 1,
          max_attempts: 5
        })

      assert result == {:error, :job_not_found}
    end

    test "returns :ok when job is already in completed state" do
      host = RunnersFixtures.runner_host_fixture()

      job =
        RunnersFixtures.runner_job_fixture(
          host: host,
          status: :running,
          vm_name: "test-vm-123"
        )

      {:ok, _} = Runners.update_runner_job(job, %{status: :cleanup})
      job = Runners.get_runner_job(job.id)
      {:ok, _} = Runners.update_runner_job(job, %{status: :completed})

      result =
        CleanupRunnerWorker.perform(%Oban.Job{
          args: %{"job_id" => job.id},
          attempt: 1,
          max_attempts: 5
        })

      assert result == :ok
    end

    test "returns :ok when job is already in failed state" do
      host = RunnersFixtures.runner_host_fixture()

      job =
        RunnersFixtures.runner_job_fixture(
          host: host,
          status: :running,
          vm_name: "test-vm-123"
        )

      {:ok, _} = Runners.update_runner_job(job, %{status: :cleanup})
      job = Runners.get_runner_job(job.id)
      {:ok, _} = Runners.update_runner_job(job, %{status: :failed})

      result =
        CleanupRunnerWorker.perform(%Oban.Job{
          args: %{"job_id" => job.id},
          attempt: 1,
          max_attempts: 5
        })

      assert result == :ok
    end

    test "marks job as completed when no host is assigned" do
      job = RunnersFixtures.runner_job_fixture(status: :running, vm_name: "test-vm-123")

      result =
        CleanupRunnerWorker.perform(%Oban.Job{
          args: %{"job_id" => job.id},
          attempt: 1,
          max_attempts: 5
        })

      assert result == :ok

      updated_job = Runners.get_runner_job(job.id)
      assert updated_job.status == :completed
      assert updated_job.completed_at
    end

    test "executes SSH cleanup and marks job as completed on success" do
      host = RunnersFixtures.runner_host_fixture()

      job =
        RunnersFixtures.runner_job_fixture(
          host: host,
          status: :running,
          github_runner_name: "tuist-runner-abc123"
        )

      connection_ref = make_ref()

      expect(SSHClient, :connect, fn _ip, _port, _opts ->
        {:ok, connection_ref}
      end)

      expect(SSHClient, :run_command, fn ^connection_ref, command, _timeout ->
        assert command =~ "pkill -f 'Runner.Listener.*tuist-runner-abc123'"
        assert command =~ "rm -rf ~/actions-runner-tuist-runner-abc123"
        {:ok, "Cleanup completed"}
      end)

      expect(SSHClient, :close, fn ^connection_ref -> :ok end)

      result =
        CleanupRunnerWorker.perform(%Oban.Job{
          args: %{"job_id" => job.id},
          attempt: 1,
          max_attempts: 5
        })

      assert result == :ok

      updated_job = Runners.get_runner_job(job.id)
      assert updated_job.status == :completed
      assert updated_job.completed_at
    end

    test "retries on SSH connection failure" do
      host = RunnersFixtures.runner_host_fixture()

      job =
        RunnersFixtures.runner_job_fixture(
          host: host,
          status: :running,
          vm_name: "test-vm-123"
        )

      expect(SSHClient, :connect, fn _ip, _port, _opts ->
        {:error, :connection_refused}
      end)

      result =
        CleanupRunnerWorker.perform(%Oban.Job{
          args: %{"job_id" => job.id},
          attempt: 1,
          max_attempts: 5
        })

      assert {:error, {:ssh_connection_failed, :connection_refused}} = result

      updated_job = Runners.get_runner_job(job.id)
      assert updated_job.status == :cleanup
    end

    test "marks job as failed after max retries" do
      host = RunnersFixtures.runner_host_fixture()

      job =
        RunnersFixtures.runner_job_fixture(
          host: host,
          status: :running,
          vm_name: "test-vm-123"
        )

      expect(SSHClient, :connect, fn _ip, _port, _opts ->
        {:error, :connection_refused}
      end)

      result =
        CleanupRunnerWorker.perform(%Oban.Job{
          args: %{"job_id" => job.id},
          attempt: 5,
          max_attempts: 5
        })

      assert result == :ok

      updated_job = Runners.get_runner_job(job.id)
      assert updated_job.status == :failed
      assert updated_job.completed_at
      assert updated_job.error_message =~ "Cleanup failed after 5 attempts"
      assert updated_job.error_message =~ "SSH connection failed"
    end

    test "handles cleanup command failure and retries" do
      host = RunnersFixtures.runner_host_fixture()

      job =
        RunnersFixtures.runner_job_fixture(
          host: host,
          status: :running,
          vm_name: "test-vm-123"
        )

      connection_ref = make_ref()

      expect(SSHClient, :connect, fn _ip, _port, _opts ->
        {:ok, connection_ref}
      end)

      expect(SSHClient, :run_command, fn ^connection_ref, _command, _timeout ->
        {:error, "return from command failed with code 1"}
      end)

      expect(SSHClient, :close, fn ^connection_ref -> :ok end)

      result =
        CleanupRunnerWorker.perform(%Oban.Job{
          args: %{"job_id" => job.id},
          attempt: 1,
          max_attempts: 5
        })

      assert {:error, {:cleanup_command_failed, _}} = result

      updated_job = Runners.get_runner_job(job.id)
      assert updated_job.status == :cleanup
    end

    test "succeeds when job is already in cleanup state" do
      host = RunnersFixtures.runner_host_fixture()

      job =
        RunnersFixtures.runner_job_fixture(
          host: host,
          status: :running,
          vm_name: "test-vm-123"
        )

      {:ok, job} = Runners.update_runner_job(job, %{status: :cleanup})

      connection_ref = make_ref()

      expect(SSHClient, :connect, fn _ip, _port, _opts ->
        {:ok, connection_ref}
      end)

      expect(SSHClient, :run_command, fn ^connection_ref, _command, _timeout ->
        {:ok, "VM deleted"}
      end)

      expect(SSHClient, :close, fn ^connection_ref -> :ok end)

      result =
        CleanupRunnerWorker.perform(%Oban.Job{
          args: %{"job_id" => job.id},
          attempt: 1,
          max_attempts: 5
        })

      assert result == :ok

      updated_job = Runners.get_runner_job(job.id)
      assert updated_job.status == :completed
    end
  end
end
