defmodule Tuist.MCP.CodebaseSearchTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.MCP.CodebaseSearch

  test "calls the bounded codebase service endpoint" do
    stub(Environment, :codebase_search_url, fn -> "http://codebase-search" end)

    expect(Req, :post, fn url, options ->
      assert url == "http://codebase-search/v1/search"
      assert options[:json] == %{"pattern" => "cache", "path" => "server"}
      assert options[:receive_timeout] == 5_500
      assert options[:connect_options] == [timeout: 1_000]

      {:ok,
       %Req.Response{
         status: 200,
         body: %{
           "revision" => "abc123",
           "query" => "cache",
           "matches" => [],
           "truncated" => false,
           "truncation_reason" => nil,
           "stats" => %{}
         }
       }}
    end)

    assert {:ok, %{"revision" => "abc123"}} =
             CodebaseSearch.search(%{"pattern" => "cache", "path" => "server"})
  end

  test "returns bounded service errors with their status" do
    stub(Environment, :codebase_search_url, fn -> "http://codebase-search" end)

    stub(Req, :post, fn _url, _options ->
      {:ok,
       %Req.Response{
         status: 400,
         body: %{"code" => "invalid_request", "error" => "max_results must be between 1 and 50"}
       }}
    end)

    assert {:error, "Tuist codebase search returned status 400: max_results must be between 1 and 50"} =
             CodebaseSearch.search(%{"pattern" => "cache", "max_results" => 51})
  end

  test "does not issue a request when the service is not configured" do
    stub(Environment, :codebase_search_url, fn -> nil end)

    assert {:error, "Tuist codebase search is not configured."} =
             CodebaseSearch.list_files(%{})
  end
end
