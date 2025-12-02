defmodule Runner.Runner.JobExecutorTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Runner.Runner.GitHub.{Auth, MessageListener, Registration, Session}
  alias Runner.Runner.JobExecutor

  describe "execute/2" do
    test "creates and cleans up working directory" do
      base_work_dir = System.tmp_dir!()
      job_id = "test-job-#{:rand.uniform(100_000)}"

      # Stub all the GitHub modules to return errors so we exit early
      Mimic.stub(Registration, :register, fn _token, _params ->
        {:error, :test_exit}
      end)

      job_config = %{
        job_id: job_id,
        github_org: "test-org",
        github_repo: nil,
        labels: ["self-hosted"],
        registration_token: "test-token",
        timeout_ms: 1000
      }

      {:ok, result} = JobExecutor.execute(job_config, base_work_dir: base_work_dir)

      # Should return error result
      assert result.result == :error
      assert result.error == :test_exit

      # Working directory should be cleaned up
      work_dir = Path.join(base_work_dir, job_id)
      refute File.exists?(work_dir)
    end

    test "full execution flow with mocked GitHub modules" do
      Mimic.stub(Registration, :register, fn _token, _params ->
        {:ok,
         %{
           runner_id: 123,
           agent_id: 123,
           pool_id: 1,
           server_url: "https://github.com/test-org",
           server_url_v2: "https://actions.githubusercontent.com/abc",
           auth_url: "https://vstoken.actions.githubusercontent.com/abc",
           rsa_private_key: "test-key",
           credentials: %{
             runner_id: "123",
             client_id: "test-client-uuid",
             rsa_private_key: "test-key",
             auth_url: "https://vstoken.actions.githubusercontent.com/abc",
             access_token: nil,
             token_expires_at: nil
           }
         }}
      end)

      Mimic.stub(Auth, :refresh_token, fn creds ->
        {:ok, Map.merge(creds, %{access_token: "test-token", token_expires_at: DateTime.utc_now() |> DateTime.add(3600, :second)})}
      end)

      Mimic.stub(Session, :create_session, fn _url, _creds, _info ->
        {:ok, %{session_id: "test-session", owner_name: "test-host"}}
      end)

      Mimic.stub(Session, :delete_session, fn _url, _creds, _session_id -> :ok end)

      test_pid = self()

      Mimic.stub(MessageListener, :start_link, fn _opts ->
        # Simulate receiving a job message after a short delay
        spawn(fn ->
          Process.sleep(50)
          send(test_pid, {:job_message, %{
            message_type: "RunnerJobRequest",
            body: %{
              "runner_request_id" => "job-123",
              "run_service_url" => "https://pipelines.actions.githubusercontent.com/abc",
              "billing_owner_id" => "owner-123"
            }
          }})
        end)
        {:ok, spawn(fn -> Process.sleep(:infinity) end)}
      end)

      Mimic.stub(MessageListener, :stop, fn _pid -> :ok end)
      Mimic.stub(MessageListener, :pause, fn _pid -> :ok end)

      # The job will timeout since we're not fully mocking JobRunner
      job_config = %{
        job_id: "test-job-#{:rand.uniform(100_000)}",
        github_org: "test-org",
        github_repo: nil,
        labels: ["self-hosted"],
        registration_token: "test-token",
        timeout_ms: 100
      }

      {:ok, _result} = JobExecutor.execute(job_config, base_work_dir: System.tmp_dir!())
    end
  end
end
