defmodule Condukt.MCP.ServerTest do
  use ExUnit.Case, async: true

  alias Condukt.MCP.Server

  describe "normalize/1 with a struct" do
    test "validates a stdio transport spec" do
      server = %Server{name: "echo", transport: {:stdio, command: "/usr/bin/echo", args: []}}
      assert {:ok, %Server{transport: {:stdio, _}}} = Server.normalize(server)
    end

    test "rejects a missing command for stdio" do
      server = %Server{name: "x", transport: {:stdio, args: []}}
      assert {:error, :stdio_command_required} = Server.normalize(server)
    end

    test "rejects an invalid name" do
      server = %Server{name: "not a name", transport: {:stdio, command: "x"}}
      assert {:error, {:invalid_server_name, "not a name"}} = Server.normalize(server)
    end

    test "rejects a missing url for streamable_http" do
      server = %Server{name: "x", transport: {:streamable_http, []}}
      assert {:error, {:url_required, :streamable_http}} = Server.normalize(server)
    end

    test "accepts client_credentials auth" do
      server = %Server{
        name: "x",
        transport: {:streamable_http, url: "https://example.com"},
        auth: {:client_credentials, token_url: "https://example.com/token", client_id: "a", client_secret: "b"}
      }

      assert {:ok, %Server{}} = Server.normalize(server)
    end
  end

  describe "from_map/1" do
    test "normalizes a stdio server map" do
      assert {:ok,
              %Server{
                name: "github",
                transport: {:stdio, opts}
              }} =
               Server.normalize(%{
                 "name" => "github",
                 "transport" => "stdio",
                 "command" => "github-mcp-server",
                 "args" => ["--verbose"]
               })

      assert Keyword.get(opts, :command) == "github-mcp-server"
      assert Keyword.get(opts, :args) == ["--verbose"]
    end

    test "normalizes a streamable_http map with bearer auth" do
      assert {:ok,
              %Server{
                name: "linear",
                transport: {:streamable_http, _},
                auth: {:bearer, {:env, "LINEAR_API_KEY"}}
              }} =
               Server.normalize(%{
                 "name" => "linear",
                 "transport" => "streamable_http",
                 "url" => "https://mcp.linear.app/mcp",
                 "auth" => %{"type" => "bearer", "env" => "LINEAR_API_KEY"}
               })
    end

    test "treats transport=http as streamable_http" do
      assert {:ok, %Server{transport: {:streamable_http, _}}} =
               Server.normalize(%{"name" => "x", "transport" => "http", "url" => "https://example.com"})
    end

    test "rejects unknown client_credentials keys without creating atoms" do
      key = "review_unknown_#{System.unique_integer([:positive])}"
      assert_raise ArgumentError, fn -> :erlang.binary_to_existing_atom(key, :utf8) end

      assert {:error, {:unknown_client_credentials_key, ^key}} =
               Server.normalize(%{
                 "name" => "x",
                 "transport" => "streamable_http",
                 "url" => "https://example.com",
                 "auth" => %{"type" => "client_credentials", key => "value"}
               })

      assert_raise ArgumentError, fn -> :erlang.binary_to_existing_atom(key, :utf8) end
    end
  end

  describe "prefix/1" do
    test "defaults to the server name" do
      assert Server.prefix(%Server{name: "github", transport: {:stdio, command: "x"}}) == "github"
    end

    test "honors the prefix override" do
      assert Server.prefix(%Server{name: "github", transport: {:stdio, command: "x"}, prefix: "gh"}) == "gh"
    end

    test "empty prefix exposes tools without a namespace" do
      assert Server.prefix(%Server{name: "github", transport: {:stdio, command: "x"}, prefix: ""}) == ""
    end
  end
end
