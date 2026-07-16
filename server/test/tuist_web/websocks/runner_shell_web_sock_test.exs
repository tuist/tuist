defmodule TuistWeb.RunnerShellWebSockTest do
  use TuistTestSupport.Cases.DataCase, async: false

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Repo
  alias Tuist.Runners.InteractiveSessions
  alias Tuist.Runners.InteractiveShellBroker
  alias TuistWeb.RunnerShellAgentWebSock
  alias TuistWeb.RunnerShellClientWebSock

  defp shell_session do
    user = user_fixture()
    account = user.account

    {:ok, session} =
      InteractiveSessions.request_shell(
        %{
          account_id: account.id,
          workflow_job_id: System.unique_integer([:positive]),
          fleet_name: "linux-amd64",
          status: "running",
          pod_name: "pod-#{System.unique_integer([:positive])}"
        },
        account,
        user
      )

    session
  end

  test "client endpoint closes the shell at the absolute session expiry" do
    session = shell_session()
    :ok = InteractiveShellBroker.subscribe_runner(session.id)

    assert {:push, {:text, status_payload}, state} = RunnerShellClientWebSock.init(%{session: session})
    assert %{"status" => "waiting"} = JSON.decode!(status_payload)

    assert {:push, {:text, exit_payload}, expired_state} =
             RunnerShellClientWebSock.handle_info({:runner_shell, :session_expired}, state)

    assert %{"type" => "exit", "status" => 255} = JSON.decode!(exit_payload)
    assert_receive {:runner_shell, :client_disconnected}
    assert Repo.reload!(session).close_reason == "expired"

    assert {:stop, :normal, ^expired_state} =
             RunnerShellClientWebSock.handle_info({:runner_shell, :close_expired_session}, expired_state)
  end

  test "agent endpoint does not overwrite a zero shell exit with a disconnect" do
    assert_agent_exit_is_terminal(0)
  end

  test "agent endpoint does not overwrite a nonzero shell exit with a disconnect" do
    assert_agent_exit_is_terminal(42)
  end

  defp assert_agent_exit_is_terminal(status) do
    session = shell_session()
    :ok = InteractiveShellBroker.subscribe_client(session.id)

    assert {:ok, state} = RunnerShellAgentWebSock.init(%{session: session})
    assert_receive {:runner_shell, :runner_connected}

    payload = JSON.encode!(%{type: "exit", status: status})
    assert {:stop, :normal, exit_state} = RunnerShellAgentWebSock.handle_in({payload, [opcode: :text]}, state)

    assert_receive {:runner_shell, {:runner_exit, ^status}}
    assert Repo.reload!(session).close_reason == "shell_exit"

    assert :ok = RunnerShellAgentWebSock.terminate(:normal, exit_state)
    refute_receive {:runner_shell, :runner_disconnected}
  end
end
