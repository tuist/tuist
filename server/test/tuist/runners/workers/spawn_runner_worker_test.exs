defmodule Tuist.Runners.Workers.SpawnRunnerWorkerTest do
  use TuistTestSupport.Cases.DataCase
  use Mimic

  alias Tuist.GitHub.App
  alias Tuist.GitHub.Client, as: GitHubClient
  alias Tuist.Runners
  alias Tuist.Runners.Workers.MonitorRunnerWorker
  alias Tuist.Runners.Workers.SpawnRunnerWorker
  alias Tuist.SSHClient
  alias TuistTestSupport.Fixtures.RunnersFixtures

  setup do
    stub(App, :get_installation_token, fn _installation_id ->
      {:ok, %{token: "github_token", expires_at: ~U[2024-04-30 10:30:31Z]}}
    end)

    :ok
  end

  describe "perform/1" do
    test "returns error when job is not found" do
      non_existent_id = UUIDv7.generate()

      result =
        SpawnRunnerWorker.perform(%Oban.Job{
          args: %{"job_id" => non_existent_id},
          attempt: 1,
          max_attempts: 3
        })

      assert result == {:error, :job_not_found}
    end

    test "returns :ok when job is already completed" do
      job = RunnersFixtures.runner_job_fixture(status: :completed)

      result =
        SpawnRunnerWorker.perform(%Oban.Job{
          args: %{"job_id" => job.id},
          attempt: 1,
          max_attempts: 3
        })

      assert result == :ok
    end

    test "returns :ok when job is already failed" do
      job = RunnersFixtures.runner_job_fixture(status: :failed)

      result =
        SpawnRunnerWorker.perform(%Oban.Job{
          args: %{"job_id" => job.id},
          attempt: 1,
          max_attempts: 3
        })

      assert result == :ok
    end

    test "returns :ok when job is already cancelled" do
      job = RunnersFixtures.runner_job_fixture(status: :cancelled)

      result =
        SpawnRunnerWorker.perform(%Oban.Job{
          args: %{"job_id" => job.id},
          attempt: 1,
          max_attempts: 3
        })

      assert result == :ok
    end

    test "returns error when no hosts are available" do
      job = RunnersFixtures.runner_job_fixture(status: :pending)

      result =
        SpawnRunnerWorker.perform(%Oban.Job{
          args: %{"job_id" => job.id},
          attempt: 1,
          max_attempts: 3
        })

      assert result == {:error, :no_hosts_available}

      updated_job = Runners.get_runner_job(job.id)
      assert updated_job.status == :failed
      assert updated_job.error_message == "No runner hosts available"
    end

    test "successfully spawns a runner and enqueues monitor" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        host = RunnersFixtures.runner_host_fixture()
        runner_org = RunnersFixtures.runner_organization_fixture()
        job = RunnersFixtures.runner_job_fixture(organization: runner_org, status: :pending)

        connection_ref = make_ref()

        expect(GitHubClient, :get_org_runner_registration_token, fn %{
                                                                      org: org,
                                                                      installation_id: _
                                                                    } ->
          assert org == job.org
          {:ok, %{token: "test-registration-token", expires_at: DateTime.utc_now()}}
        end)

        expect(SSHClient, :connect, fn _ip, _port, _opts ->
          {:ok, connection_ref}
        end)

        expect(SSHClient, :run_command, fn ^connection_ref, command, _timeout ->
          assert command =~ "config.sh"
          assert command =~ "--ephemeral"
          assert command =~ "test-registration-token"
          assert command =~ "tuist-runner-"
          {:ok, "Runner started successfully"}
        end)

        expect(SSHClient, :close, fn ^connection_ref -> :ok end)

        result =
          SpawnRunnerWorker.perform(%Oban.Job{
            args: %{"job_id" => job.id},
            attempt: 1,
            max_attempts: 3
          })

        assert result == :ok

        updated_job = Runners.get_runner_job(job.id)
        assert updated_job.status == :running
        assert updated_job.host_id == host.id
        assert updated_job.started_at
        assert updated_job.github_runner_name =~ "tuist-runner-"

        assert_enqueued(worker: MonitorRunnerWorker, args: %{job_id: job.id})
      end)
    end

    test "handles SSH connection failure and retries" do
      host = RunnersFixtures.runner_host_fixture()
      runner_org = RunnersFixtures.runner_organization_fixture()
      job = RunnersFixtures.runner_job_fixture(organization: runner_org, status: :pending)

      expect(GitHubClient, :get_org_runner_registration_token, fn _ ->
        {:ok, %{token: "test-token", expires_at: DateTime.utc_now()}}
      end)

      expect(SSHClient, :connect, fn _ip, _port, _opts ->
        {:error, :connection_refused}
      end)

      result =
        SpawnRunnerWorker.perform(%Oban.Job{
          args: %{"job_id" => job.id},
          attempt: 1,
          max_attempts: 3
        })

      assert {:error, {:ssh_connection_failed, :connection_refused}} = result

      updated_job = Runners.get_runner_job(job.id)
      assert updated_job.status == :spawning
      assert updated_job.host_id == host.id
      assert updated_job.error_message =~ "SSH connection failed"
    end

    test "marks job as failed on last attempt" do
      _host = RunnersFixtures.runner_host_fixture()
      runner_org = RunnersFixtures.runner_organization_fixture()
      job = RunnersFixtures.runner_job_fixture(organization: runner_org, status: :pending)

      expect(GitHubClient, :get_org_runner_registration_token, fn _ ->
        {:ok, %{token: "test-token", expires_at: DateTime.utc_now()}}
      end)

      expect(SSHClient, :connect, fn _ip, _port, _opts ->
        {:error, :connection_refused}
      end)

      result =
        SpawnRunnerWorker.perform(%Oban.Job{
          args: %{"job_id" => job.id},
          attempt: 3,
          max_attempts: 3
        })

      assert result == :ok

      updated_job = Runners.get_runner_job(job.id)
      assert updated_job.status == :failed
      assert updated_job.completed_at
      assert updated_job.error_message =~ "Spawn failed after 3 attempts"
      assert updated_job.error_message =~ "SSH connection failed"
    end

    test "handles runner setup command failure and retries" do
      _host = RunnersFixtures.runner_host_fixture()
      runner_org = RunnersFixtures.runner_organization_fixture()
      job = RunnersFixtures.runner_job_fixture(organization: runner_org, status: :pending)

        connection_ref = make_ref()

        expect(GitHubClient, :get_repo_runner_registration_token, fn _ ->
          {:ok, %{token: "test-token", expires_at: DateTime.utc_now()}}
        end)

        expect(SSHClient, :connect, fn _ip, _port, _opts ->
          {:ok, connection_ref}
        end)

        expect(SSHClient, :run_command, fn ^connection_ref, _command, _timeout ->
        {:error, "return from command failed with code 1"}
      end)

      expect(SSHClient, :close, fn ^connection_ref -> :ok end)

      result =
        SpawnRunnerWorker.perform(%Oban.Job{
          args: %{"job_id" => job.id},
          attempt: 1,
          max_attempts: 3
        })

      assert {:error, {:setup_command_failed, _}} = result

      updated_job = Runners.get_runner_job(job.id)
      assert updated_job.status == :spawning
      assert updated_job.error_message =~ "Runner setup failed"
    end

    test "handles GitHub registration token failure" do
      _host = RunnersFixtures.runner_host_fixture()
      runner_org = RunnersFixtures.runner_organization_fixture()
      job = RunnersFixtures.runner_job_fixture(organization: runner_org, status: :pending)

      expect(GitHubClient, :get_org_runner_registration_token, fn _ ->
        {:error, "Unauthorized"}
      end)

      result =
        SpawnRunnerWorker.perform(%Oban.Job{
          args: %{"job_id" => job.id},
          attempt: 1,
          max_attempts: 3
        })

      assert {:error, "Unauthorized"} = result

      updated_job = Runners.get_runner_job(job.id)
      assert updated_job.status == :spawning
    end

    test "resumes spawning when job is already in spawning state" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        host = RunnersFixtures.runner_host_fixture()
        runner_org = RunnersFixtures.runner_organization_fixture()
        job = RunnersFixtures.runner_job_fixture(organization: runner_org, status: :spawning)

        connection_ref = make_ref()

        expect(Req, :post, fn opts ->
          assert opts[:url] =~ "/orgs/"
          assert opts[:url] =~ "/actions/runners/registration-token"

          {:ok,
           %Req.Response{
             status: 201,
             body: %{
               "token" => "test-registration-token",
               "expires_at" => "2025-12-03T12:00:00Z"
             }
           }}
        end)

        expect(SSHClient, :connect, fn _ip, _port, _opts ->
          {:ok, connection_ref}
        end)

        expect(SSHClient, :run_command, fn ^connection_ref, _command, _timeout ->
          {:ok, "Runner started successfully"}
        end)

        expect(SSHClient, :close, fn ^connection_ref -> :ok end)

        result =
          SpawnRunnerWorker.perform(%Oban.Job{
            args: %{"job_id" => job.id},
            attempt: 1,
            max_attempts: 3
          })

        assert result == :ok

        updated_job = Runners.get_runner_job(job.id)
        assert updated_job.status == :running
        assert updated_job.host_id == host.id
      end)
    end

    test "selects host from available hosts" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        _offline_host = RunnersFixtures.runner_host_fixture(status: :offline)
        online_host = RunnersFixtures.runner_host_fixture(status: :online)
        runner_org = RunnersFixtures.runner_organization_fixture()
        job = RunnersFixtures.runner_job_fixture(organization: runner_org, status: :pending)

        connection_ref = make_ref()

        expect(Req, :post, fn opts ->
          assert opts[:url] =~ "/orgs/"
          assert opts[:url] =~ "/actions/runners/registration-token"

          {:ok,
           %Req.Response{
             status: 201,
             body: %{
               "token" => "test-registration-token",
               "expires_at" => "2025-12-03T12:00:00Z"
             }
           }}
        end)

        expect(SSHClient, :connect, fn _ip, _port, _opts ->
          {:ok, connection_ref}
        end)

        expect(SSHClient, :run_command, fn ^connection_ref, _command, _timeout ->
          {:ok, "Runner started successfully"}
        end)

        expect(SSHClient, :close, fn ^connection_ref -> :ok end)

        result =
          SpawnRunnerWorker.perform(%Oban.Job{
            args: %{"job_id" => job.id},
            attempt: 1,
            max_attempts: 3
          })

        assert result == :ok

        updated_job = Runners.get_runner_job(job.id)
        assert updated_job.host_id == online_host.id
      end)
    end
  end
end
