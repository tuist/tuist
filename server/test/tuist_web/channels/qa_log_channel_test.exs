defmodule TuistWeb.QALogChannelTest do
  use TuistWeb.ChannelCase

  import ExUnit.CaptureLog
  import TuistTestSupport.Fixtures.AccountsFixtures
  import TuistTestSupport.Fixtures.AppBuildsFixtures
  import TuistTestSupport.Fixtures.ProjectsFixtures
  import TuistTestSupport.Fixtures.QAFixtures

  alias TuistWeb.QALogChannel
  alias TuistWeb.Socket

  setup do
    organization = organization_fixture()
    account = Tuist.Repo.get_by!(Tuist.Accounts.Account, organization_id: organization.id)

    project = project_fixture(account_id: account.id)
    preview = preview_fixture(project: project)
    app_build = app_build_fixture(preview: preview)
    qa_run = qa_run_fixture(app_build: app_build)

    claims = %{
      "type" => "account",
      "scopes" => ["project:qa_run:update", "project:qa_step:create", "project:qa_screenshot:create"],
      "project_id" => project.id
    }

    {:ok, auth_token, _claims} =
      Tuist.Authentication.encode_and_sign(account, claims, token_type: :access, ttl: {1, :hour})

    {:ok, socket} =
      connect(Socket, %{"token" => auth_token}, connect_info: %{})

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
        "data" => JSON.encode!(%{"message" => "Test log message"}),
        "type" => "message",
        "timestamp" => DateTime.to_iso8601(DateTime.utc_now())
      }

      ref = push(socket, "log", log_message)
      assert_reply(ref, :ok)
    end

    test "handles multiple log messages in sequence", %{socket: socket, qa_run: qa_run} do
      {:ok, _, socket} = subscribe_and_join(socket, QALogChannel, "qa_logs:#{qa_run.id}")

      for i <- 1..3 do
        log_message = %{
          "data" => JSON.encode!(%{"message" => "Test log message #{i}"}),
          "type" => "message",
          "timestamp" => DateTime.to_iso8601(DateTime.utc_now())
        }

        ref = push(socket, "log", log_message)
        assert_reply(ref, :ok)
      end
    end

    test "handles different log types correctly", %{socket: socket, qa_run: qa_run} do
      {:ok, _, socket} = subscribe_and_join(socket, QALogChannel, "qa_logs:#{qa_run.id}")

      types = [
        {"message", %{"message" => "Test message"}},
        {"tool_call", %{"name" => "test_tool", "arguments" => %{}}},
        {"usage", %{"input" => 100, "output" => 50, "model" => "test-model"}}
      ]

      capture_log(fn ->
        for {type, data} <- types do
          log_message = %{
            "data" => JSON.encode!(data),
            "type" => type,
            "timestamp" => DateTime.to_iso8601(DateTime.utc_now())
          }

          ref = push(socket, "log", log_message)
          assert_reply(ref, :ok)
        end
      end)
    end

    test "handles token usage logs and creates token usage records", %{
      socket: socket,
      qa_run: qa_run
    } do
      {:ok, _, socket} = subscribe_and_join(socket, QALogChannel, "qa_logs:#{qa_run.id}")

      token_usage_message = %{
        "data" =>
          JSON.encode!(%{
            "input" => 150,
            "output" => 75,
            "model" => "claude-sonnet-4-20250514"
          }),
        "type" => "usage",
        "timestamp" => DateTime.to_iso8601(DateTime.utc_now())
      }

      ref = push(socket, "log", token_usage_message)
      assert_reply(ref, :ok)

      token_usage = Tuist.Billing.token_usage_for_resource("qa", qa_run.id)
      assert token_usage.total_input_tokens == 150
      assert token_usage.total_output_tokens == 75
      assert token_usage.average_tokens == 225
    end

    test "handles multiple token usage logs and accumulates totals", %{
      socket: socket,
      qa_run: qa_run
    } do
      {:ok, _, socket} = subscribe_and_join(socket, QALogChannel, "qa_logs:#{qa_run.id}")

      token_usage_1 = %{
        "data" =>
          JSON.encode!(%{
            "input" => 100,
            "output" => 50,
            "model" => "claude-sonnet-4-20250514"
          }),
        "type" => "usage",
        "timestamp" => DateTime.to_iso8601(DateTime.utc_now())
      }

      token_usage_2 = %{
        "data" =>
          JSON.encode!(%{
            "input" => 200,
            "output" => 100,
            "model" => "claude-sonnet-4-20250514"
          }),
        "type" => "usage",
        "timestamp" => DateTime.to_iso8601(DateTime.utc_now())
      }

      ref1 = push(socket, "log", token_usage_1)
      assert_reply(ref1, :ok)

      ref2 = push(socket, "log", token_usage_2)
      assert_reply(ref2, :ok)

      token_usage = Tuist.Billing.token_usage_for_resource("qa", qa_run.id)
      assert token_usage.total_input_tokens == 300
      assert token_usage.total_output_tokens == 150
      assert token_usage.average_tokens == 450
    end
  end
end
