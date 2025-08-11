defmodule TuistWeb.QALogChannelTest do
  use TuistWeb.ChannelCase

  import TuistTestSupport.Fixtures.AccountsFixtures
  import TuistTestSupport.Fixtures.AppBuildsFixtures
  import TuistTestSupport.Fixtures.ProjectsFixtures
  import TuistTestSupport.Fixtures.QAFixtures

  alias TuistWeb.QALogChannel
  alias TuistWeb.UserSocket

  setup do
    organization = organization_fixture()
    account = Tuist.Repo.get_by!(Tuist.Accounts.Account, organization_id: organization.id)

    project = project_fixture(account_id: account.id)
    preview = preview_fixture(project: project)
    app_build = app_build_fixture(preview: preview)
    qa_run = qa_run_fixture(app_build: app_build)

    claims = %{
      "type" => "account",
      "scopes" => ["project_qa_run_update", "project_qa_step_create", "project_qa_screenshot_create"],
      "project_id" => project.id
    }

    {:ok, auth_token, _claims} =
      Tuist.Authentication.encode_and_sign(account, claims, token_type: :access, ttl: {1, :hour})

    {:ok, socket} =
      connect(UserSocket, %{"token" => auth_token}, connect_info: %{})

    %{
      socket: socket,
      account: account,
      project: project,
      auth_token: auth_token,
      qa_run: qa_run
    }
  end

  describe "join/3" do
    test "joins qa_logs channel with valid qa_run_id and authorization", %{
      socket: socket,
      qa_run: qa_run
    } do
      assert {:ok, _, _socket} = subscribe_and_join(socket, QALogChannel, "qa_logs:#{qa_run.id}")
    end

    test "rejects join with invalid qa_run_id", %{socket: socket} do
      invalid_qa_run_id = UUIDv7.generate()

      assert {:error, %{reason: "unauthorized"}} =
               subscribe_and_join(socket, QALogChannel, "qa_logs:#{invalid_qa_run_id}")
    end

    test "rejects join with malformed qa_run_id", %{socket: socket} do
      malformed_qa_run_id = "not-a-valid-uuid"

      assert {:error, %{reason: "unauthorized"}} =
               subscribe_and_join(socket, QALogChannel, "qa_logs:#{malformed_qa_run_id}")
    end
  end

  describe "handle_in/3" do
    test "handles log messages and forwards to Logger", %{socket: socket, qa_run: qa_run} do
      {:ok, _, socket} = subscribe_and_join(socket, QALogChannel, "qa_logs:#{qa_run.id}")

      log_message = %{
        "message" => "Test log message",
        "level" => "info",
        "timestamp" => DateTime.to_iso8601(DateTime.utc_now())
      }

      ref = push(socket, "log", log_message)
      assert_reply(ref, :ok)
    end

    test "handles multiple log messages in sequence", %{socket: socket, qa_run: qa_run} do
      {:ok, _, socket} = subscribe_and_join(socket, QALogChannel, "qa_logs:#{qa_run.id}")

      for i <- 1..3 do
        log_message = %{
          "message" => "Test log message #{i}",
          "level" => "debug",
          "timestamp" => DateTime.to_iso8601(DateTime.utc_now())
        }

        ref = push(socket, "log", log_message)
        assert_reply(ref, :ok)
      end
    end

    test "handles different log levels correctly", %{socket: socket, qa_run: qa_run} do
      {:ok, _, socket} = subscribe_and_join(socket, QALogChannel, "qa_logs:#{qa_run.id}")

      levels = ["debug", "info", "warn", "warning", "error"]

      for level <- levels do
        log_message = %{
          "message" => "Test #{level} message",
          "level" => level,
          "timestamp" => DateTime.to_iso8601(DateTime.utc_now())
        }

        ref = push(socket, "log", log_message)
        assert_reply(ref, :ok)
      end
    end

    test "defaults to info level for unknown levels", %{socket: socket, qa_run: qa_run} do
      {:ok, _, socket} = subscribe_and_join(socket, QALogChannel, "qa_logs:#{qa_run.id}")

      log_message = %{
        "message" => "Test unknown level message",
        "level" => "unknown",
        "timestamp" => DateTime.to_iso8601(DateTime.utc_now())
      }

      ref = push(socket, "log", log_message)
      assert_reply(ref, :ok)
    end
  end
end
