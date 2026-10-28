defmodule Atlas.MCP.Tools.SearchWebTest do
  use ExUnit.Case, async: true
  use Mimic

  import Atlas.MCP.ToolCase, only: [execute_tool: 3]

  alias Atlas.MCP.Tools.SearchWeb

  setup :verify_on_exit!

  describe "execute/2" do
    test "returns ranked results from Brave Search" do
      stub(SearchWeb, :api_key, fn -> {:ok, "brave-key"} end)

      expect(Req, :get, fn opts ->
        assert opts[:url] == "https://api.search.brave.com/res/v1/web/search"
        assert {"X-Subscription-Token", "brave-key"} in opts[:headers]
        assert {"Accept", "application/json"} in opts[:headers]
        assert opts[:params][:q] == "phoenix liveview 1.0"
        assert opts[:params][:count] == 3
        assert opts[:params][:country] == "us"
        refute Keyword.has_key?(opts[:params], :freshness)

        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "web" => %{
               "results" => [
                 %{
                   "url" => "https://phoenixframework.org/blog/1.0",
                   "title" => "Phoenix LiveView 1.0 released",
                   "description" => "Stable LiveView ships with...",
                   "age" => "2 days ago"
                 },
                 %{"title" => "Missing URL — should be dropped"}
               ]
             }
           }
         }}
      end)

      assert {:ok, payload} =
               execute_tool(SearchWeb, nil, %{"query" => "phoenix liveview 1.0", "count" => 3})

      assert payload.query == "phoenix liveview 1.0"
      assert payload.count == 3

      assert [
               %{
                 url: "https://phoenixframework.org/blog/1.0",
                 title: "Phoenix LiveView 1.0 released",
                 snippet: "Stable LiveView ships with...",
                 age: "2 days ago"
               }
             ] = payload.results
    end

    test "forwards freshness and lowercases the country code" do
      stub(SearchWeb, :api_key, fn -> {:ok, "brave-key"} end)

      expect(Req, :get, fn opts ->
        assert opts[:params][:freshness] == "pw"
        assert opts[:params][:country] == "de"
        {:ok, %Req.Response{status: 200, body: %{"web" => %{"results" => []}}}}
      end)

      assert {:ok, %{results: []}} =
               execute_tool(SearchWeb, nil, %{
                 "query" => "elixir conf",
                 "freshness" => "pw",
                 "country" => "DE"
               })
    end

    test "clamps count to the supported range" do
      stub(SearchWeb, :api_key, fn -> {:ok, "brave-key"} end)

      expect(Req, :get, fn opts ->
        assert opts[:params][:count] == 10
        {:ok, %Req.Response{status: 200, body: %{}}}
      end)

      assert {:ok, %{count: 10, results: []}} =
               execute_tool(SearchWeb, nil, %{"query" => "weather", "count" => 50})
    end

    test "rejects a blank query before hitting the API" do
      reject(&Req.get/1)

      assert {:error, "query is required."} = execute_tool(SearchWeb, nil, %{"query" => "   "})
    end

    test "surfaces a missing API key" do
      stub(SearchWeb, :api_key, fn -> {:error, "Brave Search is not configured."} end)
      reject(&Req.get/1)

      assert {:error, "Brave Search is not configured."} =
               execute_tool(SearchWeb, nil, %{"query" => "anything"})
    end

    test "surfaces non-200 responses" do
      stub(SearchWeb, :api_key, fn -> {:ok, "brave-key"} end)

      expect(Req, :get, fn _opts ->
        {:ok, %Req.Response{status: 429, body: %{"message" => "rate limited"}}}
      end)

      assert {:error, message} = execute_tool(SearchWeb, nil, %{"query" => "anything"})
      assert message =~ "HTTP 429"
      assert message =~ "rate limited"
    end

    test "surfaces transport errors" do
      stub(SearchWeb, :api_key, fn -> {:ok, "brave-key"} end)

      expect(Req, :get, fn _opts -> {:error, %Req.TransportError{reason: :timeout}} end)

      assert {:error, message} = execute_tool(SearchWeb, nil, %{"query" => "anything"})
      assert message =~ "Brave Search request failed"
      assert message =~ "timeout"
    end
  end

  describe "MCP descriptor" do
    test "advertises the expected name and schema" do
      assert SearchWeb.name() == "search_web"

      schema = SearchWeb.input_schema()
      assert schema["required"] == ["query"]
      assert schema["properties"]["count"]["maximum"] == 10
      assert schema["properties"]["freshness"]["enum"] == ["pd", "pw", "pm", "py"]
    end
  end
end
