defmodule Tuist.MCP.ServerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.MCP.Server
  alias Tuist.Projects

  describe "handle_request/2" do
    test "returns initialize result" do
      request = %{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize", "params" => %{}}
      response = Server.handle_request(request, nil)

      assert response.jsonrpc == "2.0"
      assert response.id == 1
      assert response.result.protocolVersion == "2025-03-26"
      assert response.result.serverInfo.name == "tuist"
      assert response.result.capabilities.tools
      assert response.result.capabilities.prompts
    end

    test "returns nil for notifications/initialized" do
      request = %{"jsonrpc" => "2.0", "method" => "notifications/initialized", "params" => %{}}
      assert is_nil(Server.handle_request(request, nil))
    end

    test "returns nil for other notifications" do
      request = %{"jsonrpc" => "2.0", "method" => "notifications/cancelled", "params" => %{}}
      assert is_nil(Server.handle_request(request, nil))
    end

    test "returns tools list" do
      request = %{"jsonrpc" => "2.0", "id" => 2, "method" => "tools/list", "params" => %{}}
      response = Server.handle_request(request, nil)

      assert response.id == 2
      tools = response.result.tools
      assert is_list(tools)
      assert length(tools) == 4
    end

    test "returns prompts list" do
      request = %{"jsonrpc" => "2.0", "id" => 3, "method" => "prompts/list", "params" => %{}}
      response = Server.handle_request(request, nil)

      assert response.id == 3
      prompts = response.result.prompts
      assert is_list(prompts)
      assert length(prompts) == 1
    end

    test "calls list_projects tool" do
      stub(Projects, :list_accessible_projects, fn _subject, _opts -> [] end)

      request = %{
        "jsonrpc" => "2.0",
        "id" => 4,
        "method" => "tools/call",
        "params" => %{"name" => "list_projects", "arguments" => %{}}
      }

      response = Server.handle_request(request, nil)

      assert response.id == 4
      content = response.result.content
      assert hd(content).type == "text"
      assert Jason.decode!(hd(content).text) == []
    end

    test "returns error for unknown tool" do
      request = %{
        "jsonrpc" => "2.0",
        "id" => 5,
        "method" => "tools/call",
        "params" => %{"name" => "nonexistent", "arguments" => %{}}
      }

      response = Server.handle_request(request, nil)

      assert response.id == 5
      assert response.error.code == -32_602
      assert response.error.message =~ "Unknown tool"
    end

    test "returns error for unknown method" do
      request = %{"jsonrpc" => "2.0", "id" => 6, "method" => "foo/bar", "params" => %{}}
      response = Server.handle_request(request, nil)

      assert response.id == 6
      assert response.error.code == -32_601
      assert response.error.message == "Method not found."
    end

    test "returns error for invalid request (missing method)" do
      response = Server.handle_request(%{"jsonrpc" => "2.0", "id" => 7}, nil)

      assert response.id == nil
      assert response.error.code == -32_600
    end

    test "returns error for tools/call without required params" do
      request = %{
        "jsonrpc" => "2.0",
        "id" => 8,
        "method" => "tools/call",
        "params" => %{}
      }

      response = Server.handle_request(request, nil)

      assert response.id == 8
      assert response.error.code == -32_602
    end

    test "returns error for prompts/get without name" do
      request = %{
        "jsonrpc" => "2.0",
        "id" => 9,
        "method" => "prompts/get",
        "params" => %{}
      }

      response = Server.handle_request(request, nil)

      assert response.id == 9
      assert response.error.code == -32_602
    end

    test "returns error for unknown prompt" do
      request = %{
        "jsonrpc" => "2.0",
        "id" => 10,
        "method" => "prompts/get",
        "params" => %{"name" => "nonexistent"}
      }

      response = Server.handle_request(request, nil)

      assert response.id == 10
      assert response.error.code == -32_602
      assert response.error.message =~ "Unknown prompt"
    end

    test "returns prompt messages for fix_flaky_test" do
      request = %{
        "jsonrpc" => "2.0",
        "id" => 11,
        "method" => "prompts/get",
        "params" => %{
          "name" => "fix_flaky_test",
          "arguments" => %{"test_case_id" => "abc-123"}
        }
      }

      response = Server.handle_request(request, nil)

      assert response.id == 11
      messages = response.result.messages
      assert length(messages) == 1
      assert hd(messages).role == "user"
      assert hd(messages).content.text =~ "Fix Flaky Test"
      assert hd(messages).content.text =~ "abc-123"
    end
  end
end
