defmodule Tuist.MCP.ServerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Hermes.Server.Frame
  alias Tuist.MCP.Server
  alias Tuist.Projects
  alias Tuist.Tests

  describe "handle_request/2" do
    test "returns tools list" do
      request = %{"method" => "tools/list", "params" => %{}}

      assert {:reply, %{"tools" => tools}, _frame} = Server.handle_request(request, Frame.new())

      assert Enum.map(tools, & &1.name) == [
               "get_test_case",
               "get_test_case_run",
               "get_test_run",
               "list_projects",
               "list_test_cases"
             ]
    end

    test "returns prompts list" do
      request = %{"method" => "prompts/list", "params" => %{}}

      assert {:reply, %{"prompts" => prompts}, _frame} = Server.handle_request(request, Frame.new())

      assert Enum.map(prompts, & &1.name) == ["fix_flaky_test"]
    end

    test "calls list_projects tool" do
      stub(Projects, :list_accessible_projects, fn _subject, _opts -> [] end)

      request = %{
        "method" => "tools/call",
        "params" => %{"name" => "list_projects", "arguments" => %{}}
      }

      frame = Frame.new(%{current_subject: :subject})

      assert {:reply, %{"content" => [%{"type" => "text", "text" => text}]}, _frame} =
               Server.handle_request(request, frame)

      assert JSON.decode!(text) == []
    end

    test "returns error for unknown tool" do
      request = %{
        "method" => "tools/call",
        "params" => %{"name" => "nonexistent", "arguments" => %{}}
      }

      assert {:error, error, _frame} = Server.handle_request(request, Frame.new())

      assert error.code == -32_602
      assert error.message == "Invalid params"
      assert message(error) == "Tool not found: nonexistent"
    end

    test "returns error for unknown method" do
      request = %{"method" => "foo/bar", "params" => %{}}

      assert {:error, error, _frame} = Server.handle_request(request, Frame.new())

      assert error.code == -32_601
      assert error.message == "Method not found"
    end

    test "returns error for tools/call without required params" do
      request = %{"method" => "tools/call", "params" => %{}}

      assert {:error, error, _frame} = Server.handle_request(request, Frame.new())

      assert error.code == -32_602
      assert message(error) == "Missing required parameter: name."
    end

    test "returns error for prompts/get without name" do
      request = %{"method" => "prompts/get", "params" => %{}}

      assert {:error, error, _frame} = Server.handle_request(request, Frame.new())

      assert error.code == -32_602
      assert message(error) == "Missing required parameter: name."
    end

    test "returns error for unknown prompt" do
      request = %{
        "method" => "prompts/get",
        "params" => %{"name" => "nonexistent", "arguments" => %{}}
      }

      assert {:error, error, _frame} = Server.handle_request(request, Frame.new())

      assert error.code == -32_602
      assert error.message == "Invalid params"
      assert message(error) == "Prompt not found: nonexistent"
    end

    test "returns prompt messages for fix_flaky_test" do
      request = %{
        "method" => "prompts/get",
        "params" => %{
          "name" => "fix_flaky_test",
          "arguments" => %{"test_case_id" => "abc-123"}
        }
      }

      assert {:reply, %{"messages" => messages}, _frame} = Server.handle_request(request, Frame.new())

      assert length(messages) == 1
      assert hd(messages)["role"] == "user"
      assert hd(messages)["content"]["text"] =~ "Fix Flaky Test"
      assert hd(messages)["content"]["text"] =~ "abc-123"
    end
  end

  describe "tool authorization" do
    test "requires :test_read to list test cases" do
      project = %{id: "project-id", name: "project-name"}
      stub(Projects, :get_project_by_account_and_project_handles, fn "acme", "app" -> project end)

      expect(Tuist.Authorization, :authorize, fn :test_read, :subject, ^project ->
        {:error, :forbidden}
      end)

      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "list_test_cases",
          "arguments" => %{"account_handle" => "acme", "project_handle" => "app"}
        }
      }

      frame = Frame.new(%{current_subject: :subject})

      assert {:error, error, _frame} = Server.handle_request(request, frame)
      assert error.code == -32_602
      assert message(error) == "You do not have access to project: acme/app"
    end

    test "requires :test_read to read a test case by id" do
      project = %{id: "project-id", name: "project-name"}
      project_id = project.id
      stub(Tests, :get_test_case_by_id, fn "test-case-id" -> {:ok, %{project_id: project.id}} end)
      stub(Projects, :get_project_by_id, fn ^project_id -> project end)

      expect(Tuist.Authorization, :authorize, fn :test_read, :subject, ^project ->
        {:error, :forbidden}
      end)

      request = %{
        "method" => "tools/call",
        "params" => %{"name" => "get_test_case", "arguments" => %{"test_case_id" => "test-case-id"}}
      }

      frame = Frame.new(%{current_subject: :subject})

      assert {:error, error, _frame} = Server.handle_request(request, frame)
      assert error.code == -32_602
      assert message(error) == "You do not have access to this resource."
    end

    test "requires :test_read to read a test case by identifier" do
      project = %{id: "project-id", name: "project-name"}

      stub(Projects, :get_project_by_account_and_project_handles, fn "acme", "app" -> project end)

      expect(Tuist.Authorization, :authorize, fn :test_read, :subject, ^project ->
        {:error, :forbidden}
      end)

      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "get_test_case",
          "arguments" => %{
            "account_handle" => "acme",
            "project_handle" => "app",
            "identifier" => "AuthTests/LoginSuite/testLogin"
          }
        }
      }

      frame = Frame.new(%{current_subject: :subject})

      assert {:error, error, _frame} = Server.handle_request(request, frame)
      assert error.code == -32_602
      assert message(error) == "You do not have access to project: acme/app"
    end

    test "returns error when get_test_case is called without test_case_id or identifier" do
      request = %{
        "method" => "tools/call",
        "params" => %{"name" => "get_test_case", "arguments" => %{}}
      }

      frame = Frame.new(%{current_subject: :subject})

      assert {:error, error, _frame} = Server.handle_request(request, frame)
      assert error.code == -32_602

      assert message(error) ==
               "Provide either test_case_id or identifier with account_handle and project_handle."
    end

    test "requires :test_read to read a test case run" do
      project = %{id: "project-id", name: "project-name"}
      project_id = project.id

      stub(Tests, :get_test_case_run_by_id, fn "run-id", [preload: [:failures, :repetitions]] ->
        {:ok, %{project_id: project.id}}
      end)

      stub(Projects, :get_project_by_id, fn ^project_id -> project end)

      expect(Tuist.Authorization, :authorize, fn :test_read, :subject, ^project ->
        {:error, :forbidden}
      end)

      request = %{
        "method" => "tools/call",
        "params" => %{"name" => "get_test_case_run", "arguments" => %{"test_case_run_id" => "run-id"}}
      }

      frame = Frame.new(%{current_subject: :subject})

      assert {:error, error, _frame} = Server.handle_request(request, frame)
      assert error.code == -32_602
      assert message(error) == "You do not have access to this resource."
    end

    test "requires :test_read to read a test run" do
      project = %{id: "project-id", name: "project-name"}
      project_id = project.id
      stub(Tests, :get_test, fn "test-run-id" -> {:ok, %{id: "test-run-id", project_id: project.id}} end)
      stub(Projects, :get_project_by_id, fn ^project_id -> project end)

      expect(Tuist.Authorization, :authorize, fn :test_read, :subject, ^project ->
        {:error, :forbidden}
      end)

      request = %{
        "method" => "tools/call",
        "params" => %{"name" => "get_test_run", "arguments" => %{"test_run_id" => "test-run-id"}}
      }

      frame = Frame.new(%{current_subject: :subject})

      assert {:error, error, _frame} = Server.handle_request(request, frame)
      assert error.code == -32_602
      assert message(error) == "You do not have access to this resource."
    end
  end

  defp message(error), do: Map.get(error.data, :message) || Map.get(error.data, "message")
end
