defmodule Tuist.Sandboxes.Anthropic.ControlPlaneTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.Sandboxes.Anthropic.ControlPlane

  setup do
    stub(Environment, :anthropic_api_url, fn -> "https://anthropic.test" end)
    :ok
  end

  defp assert_authenticated(%Req.Request{} = request) do
    assert request.options.base_url == "https://anthropic.test"
    assert Req.Request.get_header(request, "x-api-key") == ["sk-ant-api"]
    assert Req.Request.get_header(request, "authorization") == []
    assert Req.Request.get_header(request, "anthropic-version") == ["2023-06-01"]
    assert Req.Request.get_header(request, "anthropic-beta") == ["managed-agents-2026-04-01"]
  end

  test "create_agent/2 posts the agent definition with the default toolset" do
    expect(Req, :post, fn request, opts ->
      assert_authenticated(request)
      assert opts[:url] == "/v1/agents"

      assert opts[:json] == %{
               name: "tuist-acme",
               model: "claude-sonnet-5",
               system: "Be helpful.",
               tools: [%{type: "agent_toolset_20260401"}]
             }

      {:ok, %Req.Response{status: 200, body: %{"id" => "agent_1", "version" => 1}}}
    end)

    assert {:ok, %{"id" => "agent_1"}} =
             ControlPlane.create_agent("sk-ant-api", %{
               name: "tuist-acme",
               model: "claude-sonnet-5",
               system: "Be helpful."
             })
  end

  test "create_session/2 sends the first message, the metadata and the budget as a USD list-cost limit" do
    expect(Req, :post, fn request, opts ->
      assert_authenticated(request)
      assert opts[:url] == "/v1/sessions"

      assert opts[:json] == %{
               agent: "agent_1",
               environment_id: "env_1",
               title: "Fix the build",
               metadata: %{"tuist_account" => "acme"},
               initial_events: [%{type: "user.message", content: [%{type: "text", text: "Fix it"}]}],
               budget: %{type: "limit", max_list_cost: %{amount: "2500", currency: "USD"}}
             }

      {:ok, %Req.Response{status: 200, body: %{"id" => "sesn_1", "status" => "running"}}}
    end)

    assert {:ok, %{"id" => "sesn_1"}} =
             ControlPlane.create_session("sk-ant-api", %{
               agent: "agent_1",
               environment_id: "env_1",
               title: "Fix the build",
               metadata: %{"tuist_account" => "acme"},
               initial_events: [ControlPlane.user_message("Fix it")],
               budget_cents: 2500
             })
  end

  test "create_session/2 omits the optional fields it is not given" do
    expect(Req, :post, fn _request, opts ->
      assert opts[:json] == %{agent: "agent_1", environment_id: "env_1"}
      {:ok, %Req.Response{status: 200, body: %{"id" => "sesn_1"}}}
    end)

    assert {:ok, _session} =
             ControlPlane.create_session("sk-ant-api", %{
               agent: "agent_1",
               environment_id: "env_1",
               title: nil,
               budget_cents: nil
             })
  end

  test "get_session/2, list_events/3, send_message/3 and archive_session/2 address the session" do
    expect(Req, :get, fn request, opts ->
      assert_authenticated(request)
      assert opts[:url] == "/v1/sessions/sesn_1"
      {:ok, %Req.Response{status: 200, body: %{"id" => "sesn_1", "status" => "idle"}}}
    end)

    assert {:ok, %{"status" => "idle"}} = ControlPlane.get_session("sk-ant-api", "sesn_1")

    expect(Req, :get, fn _request, opts ->
      assert opts[:url] == "/v1/sessions/sesn_1/events"
      assert opts[:params] == [limit: 1000]
      {:ok, %Req.Response{status: 200, body: %{"data" => [%{"type" => "user.message"}]}}}
    end)

    assert {:ok, [%{"type" => "user.message"}]} = ControlPlane.list_events("sk-ant-api", "sesn_1")

    expect(Req, :get, fn _request, opts ->
      assert Enum.sort(opts[:params]) == [limit: 5, order: "desc"]
      {:ok, %Req.Response{status: 200, body: %{"data" => []}}}
    end)

    assert {:ok, []} = ControlPlane.list_events("sk-ant-api", "sesn_1", limit: 5, order: "desc")

    expect(Req, :post, fn _request, opts ->
      assert opts[:url] == "/v1/sessions/sesn_1/events"
      assert opts[:json] == %{events: [%{type: "user.message", content: [%{type: "text", text: "continue"}]}]}
      {:ok, %Req.Response{status: 200, body: %{"data" => [%{"id" => "sevt_1", "type" => "user.message"}]}}}
    end)

    assert {:ok, %{"data" => [_sent]}} = ControlPlane.send_message("sk-ant-api", "sesn_1", "continue")

    expect(Req, :post, fn _request, opts ->
      assert opts[:url] == "/v1/sessions/sesn_1/archive"
      assert opts[:json] == %{}
      {:ok, %Req.Response{status: 200, body: %{"id" => "sesn_1", "archived_at" => "2026-09-05T10:00:00Z"}}}
    end)

    assert {:ok, %{"archived_at" => _at}} = ControlPlane.archive_session("sk-ant-api", "sesn_1")
  end

  test "maps error answers to the status and Anthropic's message" do
    expect(Req, :post, fn _request, _opts ->
      body = %{"type" => "error", "error" => %{"type" => "invalid_request_error", "message" => "environment not found"}}
      {:ok, %Req.Response{status: 400, body: body}}
    end)

    assert {:error, %{status: 400, message: "environment not found"}} =
             ControlPlane.create_session("sk-ant-api", %{agent: "agent_1", environment_id: "env_1"})

    expect(Req, :get, fn _request, _opts -> {:ok, %Req.Response{status: 401, body: "unauthorized"}} end)
    assert {:error, %{status: 401, message: "unauthorized"}} = ControlPlane.get_session("sk-ant-api", "sesn_1")

    expect(Req, :get, fn _request, _opts -> {:error, %Req.TransportError{reason: :econnrefused}} end)

    assert {:error, %Req.TransportError{reason: :econnrefused}} =
             ControlPlane.list_events("sk-ant-api", "sesn_1", [])
  end
end
