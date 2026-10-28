defmodule Atlas.MCP.Tools.BrowseUrlTest do
  use ExUnit.Case, async: true
  use Mimic

  import Atlas.MCP.ToolCase, only: [execute_tool: 3]

  alias Atlas.Browser
  alias Atlas.MCP.Tools.BrowseUrl

  setup :verify_on_exit!

  describe "execute/2" do
    test "returns the rendered payload from Atlas.Browser" do
      expect(Browser, :render, fn "https://example.com" ->
        {:ok,
         %{
           title: "Example Domain",
           url: "https://example.com/",
           content: "This domain is for use in illustrative examples.",
           truncated: false
         }}
      end)

      assert {:ok, payload} = execute_tool(BrowseUrl, nil, %{"url" => "https://example.com"})
      assert payload.title == "Example Domain"
      assert payload.url == "https://example.com/"
      assert payload.content =~ "illustrative examples"
      refute payload.truncated
    end

    test "rejects URLs with non-http schemes before hitting the browser" do
      reject(&Browser.render/1)

      assert {:error, "Only http and https URLs are supported."} =
               execute_tool(BrowseUrl, nil, %{"url" => "file:///etc/passwd"})
    end

    test "rejects URLs pointing at private network hosts" do
      reject(&Browser.render/1)

      assert {:error, message} = execute_tool(BrowseUrl, nil, %{"url" => "http://10.0.0.1/admin"})
      assert message =~ "local or private"
    end

    test "rejects URLs without a hostname" do
      reject(&Browser.render/1)

      assert {:error, "The URL must include a hostname."} =
               execute_tool(BrowseUrl, nil, %{"url" => "https://"})
    end

    test "rejects URLs with embedded credentials" do
      reject(&Browser.render/1)

      assert {:error, "Credentials in URLs are not supported."} =
               execute_tool(BrowseUrl, nil, %{"url" => "https://user:pass@example.com/"})
    end

    test "surfaces a missing browser pool" do
      expect(Browser, :render, fn _url -> {:error, :browser_pool_not_started} end)

      assert {:error, "The headless browser pool is not running in this environment."} =
               execute_tool(BrowseUrl, nil, %{"url" => "https://example.com"})
    end

    test "surfaces renderer errors" do
      expect(Browser, :render, fn _url -> {:error, "navigation timed out"} end)

      assert {:error, "navigation timed out"} =
               execute_tool(BrowseUrl, nil, %{"url" => "https://example.com"})
    end

    test "requires the url argument" do
      reject(&Browser.render/1)

      assert {:error, "url is required."} = execute_tool(BrowseUrl, nil, %{})
    end
  end

  describe "MCP descriptor" do
    test "advertises the expected name and schema" do
      assert BrowseUrl.name() == "browse_url"

      schema = BrowseUrl.input_schema()
      assert schema["required"] == ["url"]
      assert schema["properties"]["url"]["type"] == "string"
    end
  end
end
