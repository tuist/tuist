defmodule Tuist.Sandboxes.Anthropic.ClientTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.Sandboxes.Anthropic.Client

  setup do
    stub(Environment, :anthropic_api_url, fn -> "https://anthropic.test" end)
    :ok
  end

  defp assert_authenticated(%Req.Request{} = request) do
    assert request.options.base_url == "https://anthropic.test"
    assert Req.Request.get_header(request, "authorization") == ["Bearer sk-ant-key"]
    assert Req.Request.get_header(request, "anthropic-version") == ["2023-06-01"]
    assert Req.Request.get_header(request, "anthropic-beta") == ["managed-agents-2026-04-01"]
  end

  describe "poll/4" do
    test "returns the work item with the worker id and block_ms on the request" do
      item = %{"id" => "work_1", "data" => %{"id" => "session_1", "type" => "session"}, "secret" => "s"}

      expect(Req, :get, fn request, opts ->
        assert_authenticated(request)
        assert Req.Request.get_header(request, "anthropic-worker-id") == ["tuist-worker"]
        assert opts[:url] == "/v1/environments/env_1/work/poll"
        assert opts[:params] == [block_ms: 999]
        assert opts[:receive_timeout] == 10_999
        {:ok, %Req.Response{status: 200, body: item}}
      end)

      assert {:ok, ^item} = Client.poll("env_1", "sk-ant-key", "tuist-worker", 5_000)
    end

    test "treats an empty answer as no work" do
      expect(Req, :get, fn _request, _opts -> {:ok, %Req.Response{status: 204, body: ""}} end)
      assert {:ok, :none} = Client.poll("env_1", "sk-ant-key", "tuist-worker")

      expect(Req, :get, fn _request, _opts -> {:ok, %Req.Response{status: 200, body: ""}} end)
      assert {:ok, :none} = Client.poll("env_1", "sk-ant-key", "tuist-worker")
    end

    test "maps rate limits, auth failures and transport errors" do
      expect(Req, :get, fn _request, _opts ->
        {:ok, %Req.Response{status: 429, body: %{}, headers: %{"retry-after" => ["3"]}}}
      end)

      assert {:error, :rate_limited} = Client.poll("env_1", "sk-ant-key", "tuist-worker")

      expect(Req, :get, fn _request, _opts -> {:ok, %Req.Response{status: 401, body: %{}}} end)
      assert {:error, :unauthorized} = Client.poll("env_1", "sk-ant-key", "tuist-worker")

      expect(Req, :get, fn _request, _opts -> {:error, %Req.TransportError{reason: :econnrefused}} end)
      assert {:error, %Req.TransportError{reason: :econnrefused}} = Client.poll("env_1", "sk-ant-key", "tuist-worker")
    end
  end

  describe "ack/3, stop/4 and stats/2" do
    test "ack posts to the work item's ack path" do
      expect(Req, :post, fn request, opts ->
        assert_authenticated(request)
        assert opts[:url] == "/v1/environments/env_1/work/work_1/ack"
        assert opts[:json] == %{}
        {:ok, %Req.Response{status: 200, body: %{"id" => "work_1", "state" => "starting"}}}
      end)

      assert {:ok, %{"state" => "starting"}} = Client.ack("env_1", "sk-ant-key", "work_1")
    end

    test "stop posts the force flag" do
      expect(Req, :post, fn _request, opts ->
        assert opts[:url] == "/v1/environments/env_1/work/work_1/stop"
        assert opts[:json] == %{force: true}
        {:ok, %Req.Response{status: 200, body: %{"id" => "work_1", "state" => "stopping"}}}
      end)

      assert {:ok, %{"state" => "stopping"}} = Client.stop("env_1", "sk-ant-key", "work_1")

      expect(Req, :post, fn _request, opts ->
        assert opts[:json] == %{force: false}
        {:ok, %Req.Response{status: 500, body: %{"error" => %{"message" => "boom"}}}}
      end)

      assert {:error, {:http, 500, "boom"}} = Client.stop("env_1", "sk-ant-key", "work_1", false)
    end

    test "stats reads the queue statistics" do
      expect(Req, :get, fn _request, opts ->
        assert opts[:url] == "/v1/environments/env_1/work/stats"
        {:ok, %Req.Response{status: 200, body: %{"depth" => 2, "pending" => 1}}}
      end)

      assert {:ok, %{"depth" => 2, "pending" => 1}} = Client.stats("env_1", "sk-ant-key")
    end

    test "url-encodes identifiers" do
      expect(Req, :post, fn _request, opts ->
        assert opts[:url] == "/v1/environments/env%2F1/work/work%201/ack"
        {:ok, %Req.Response{status: 200, body: %{}}}
      end)

      assert {:ok, %{}} = Client.ack("env/1", "sk-ant-key", "work 1")
    end
  end
end
