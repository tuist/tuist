defmodule PulseWeb.MCPTransportTest do
  # Conformance with the MCP 2026-07-28 Streamable HTTP transport.
  use PulseWeb.ConnCase, async: true

  alias Pulse.Test.MCPMessages

  @version "2026-07-28"
  @meta_version "io.modelcontextprotocol/protocolVersion"

  describe "stateless requests" do
    test "a first tools/call needs no handshake", %{conn: conn} do
      response =
        conn
        |> post_mcp(call("query_logs", %{"tenant" => "acme", "limit" => "bad"}))
        |> json_response(200)

      assert response["id"] == 1
      assert response["result"]["resultType"] == "complete"
      assert response["result"]["isError"] == true
      assert response["result"]["_meta"]["io.modelcontextprotocol/serverInfo"]["name"] == "pulse"
    end

    test "server/discover advertises versions, capabilities, and caching", %{conn: conn} do
      result =
        conn |> post_mcp(MCPMessages.request("d", "server/discover")) |> json_response(200) |> Map.fetch!("result")

      assert result["supportedVersions"] == [@version]

      assert result["capabilities"] == %{
               "tools" => %{"listChanged" => false},
               "resources" => %{"listChanged" => false, "subscribe" => true}
             }

      assert result["resultType"] == "complete"
      assert is_integer(result["ttlMs"]) and result["ttlMs"] >= 0
      assert result["cacheScope"] == "private"
      assert result["_meta"]["io.modelcontextprotocol/serverInfo"]["name"] == "pulse"
    end

    test "tools/list is cacheable and deterministic", %{conn: conn} do
      first = conn |> post_mcp(MCPMessages.request(1, "tools/list")) |> json_response(200)
      second = build_conn() |> post_mcp(MCPMessages.request(2, "tools/list")) |> json_response(200)

      assert first["result"]["tools"] == second["result"]["tools"]
      assert first["result"]["cacheScope"] == "private"
      assert is_integer(first["result"]["ttlMs"])
      assert first["result"]["resultType"] == "complete"
    end

    test "string and zero identifiers are preserved", %{conn: conn} do
      assert %{"id" => 0} = conn |> post_mcp(MCPMessages.request(0, "tools/list")) |> json_response(200)
      assert %{"id" => "abc"} = build_conn() |> post_mcp(MCPMessages.request("abc", "tools/list")) |> json_response(200)
    end

    test "session and resumption headers are ignored and never echoed", %{conn: conn} do
      conn =
        conn
        |> put_req_header("mcp-session-id", "abc")
        |> put_req_header("last-event-id", "1")
        |> post_mcp(MCPMessages.request(1, "tools/list"))

      assert json_response(conn, 200)["result"]["tools"]
      assert get_resp_header(conn, "mcp-session-id") == []
    end

    test "query strings cannot supply protocol fields", %{conn: conn} do
      message = Map.delete(MCPMessages.request(1, "tools/list"), "jsonrpc")

      response =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("mcp-protocol-version", @version)
        |> put_req_header("mcp-method", "tools/list")
        |> post("/mcp?jsonrpc=2.0", JSON.encode!(message))
        |> json_response(400)

      assert response["error"]["code"] == -32_600
    end
  end

  describe "request metadata" do
    test "missing or malformed _meta is invalid params", %{conn: conn} do
      base = MCPMessages.request(1, "tools/list")

      for params <- [
            %{},
            %{"_meta" => "x"},
            %{"_meta" => Map.delete(MCPMessages.meta(), @meta_version)},
            %{"_meta" => Map.delete(MCPMessages.meta(), "io.modelcontextprotocol/clientCapabilities")},
            %{"_meta" => MCPMessages.meta(%{"io.modelcontextprotocol/clientCapabilities" => []})},
            %{"_meta" => MCPMessages.meta(%{"io.modelcontextprotocol/clientInfo" => %{"name" => 1}})}
          ] do
        response = build_conn() |> post_mcp(Map.put(base, "params", params)) |> json_response(400)
        assert response["error"]["code"] == -32_602
        assert response["id"] == 1
      end

      assert %{"error" => %{"code" => -32_602}} =
               conn |> post_mcp(Map.delete(base, "params")) |> json_response(400)
    end

    test "client info is optional and capabilities may be empty", %{conn: conn} do
      message =
        put_in(
          MCPMessages.request(1, "tools/list"),
          ["params", "_meta"],
          Map.delete(MCPMessages.meta(), "io.modelcontextprotocol/clientInfo")
        )

      assert conn |> post_mcp(message) |> json_response(200)
    end

    test "an unsupported version lists the supported ones", %{conn: conn} do
      message = put_in(MCPMessages.request(1, "tools/list"), ["params", "_meta", @meta_version], "1900-01-01")

      response = conn |> post_mcp(message, version: "1900-01-01") |> json_response(400)

      assert response["error"]["code"] == -32_022
      assert response["error"]["data"] == %{"supported" => [@version], "requested" => "1900-01-01"}
    end
  end

  describe "mirrored headers" do
    test "each required header must be present", %{conn: conn} do
      for header <- ["mcp-protocol-version", "mcp-method", "mcp-name"] do
        response =
          build_conn()
          |> post_mcp(call("query_logs", %{"tenant" => "acme"}), omit: header)
          |> json_response(400)

        assert response["error"]["code"] == -32_020
        assert response["id"] == 1
      end

      # Mcp-Name is only required for named methods.
      assert conn |> post_mcp(MCPMessages.request(1, "tools/list"), omit: "mcp-name") |> json_response(200)
    end

    test "header values must match the body", %{conn: conn} do
      for opts <- [[version: "2025-11-25"], [method: "tools/list"], [name: "query_metrics"]] do
        response =
          build_conn()
          |> post_mcp(call("query_logs", %{"tenant" => "acme"}), opts)
          |> json_response(400)

        assert response["error"]["code"] == -32_020
      end

      assert %{"error" => %{"code" => -32_020}} =
               conn |> post_mcp(call("query_logs", %{}), name: "QUERY_LOGS") |> json_response(400)
    end

    test "a mismatch is reported before an unsupported version", %{conn: conn} do
      message = put_in(MCPMessages.request(1, "tools/list"), ["params", "_meta", @meta_version], "1900-01-01")

      assert %{"error" => %{"code" => -32_020}} = conn |> post_mcp(message, version: @version) |> json_response(400)
    end

    test "missing body metadata with valid headers stays invalid params", %{conn: conn} do
      message = put_in(MCPMessages.request(1, "tools/list"), ["params", "_meta"], %{})

      assert %{"error" => %{"code" => -32_602}} = conn |> post_mcp(message) |> json_response(400)
    end

    test "duplicate and invalid header values are rejected", %{conn: conn} do
      conn =
        conn
        |> Plug.Conn.put_req_header("mcp-method", "tools/list")
        |> Map.update!(:req_headers, &[{"mcp-method", "tools/list"} | &1])

      assert %{"error" => %{"code" => -32_020}} =
               conn |> post_mcp(MCPMessages.request(1, "tools/list"), omit: "mcp-method") |> json_response(400)

      assert %{"error" => %{"code" => -32_020}} =
               build_conn()
               |> post_mcp(call("query_logs", %{}), name: "query_logsé")
               |> json_response(400)
    end

    test "Base64-encoded names are decoded before comparison", %{conn: conn} do
      encoded = "=?base64?" <> Base.encode64("query_logs") <> "?="

      assert %{"result" => %{"isError" => true}} =
               conn
               |> post_mcp(call("query_logs", %{"tenant" => "acme", "limit" => "bad"}), name: encoded)
               |> json_response(200)

      for bad <- ["=?base64?not base64?=", "=?base64?" <> Base.encode64(<<255>>) <> "?=", "=?base64?abc"] do
        assert %{"error" => %{"code" => -32_020}} =
                 build_conn() |> post_mcp(call("query_logs", %{}), name: bad) |> json_response(400)
      end
    end

    test "a legacy initialize gets a header error naming supported versions", %{conn: conn} do
      message = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "initialize",
        "params" => %{
          "protocolVersion" => "2025-03-26",
          "capabilities" => %{},
          "clientInfo" => %{"name" => "x", "version" => "1"}
        }
      }

      response =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/mcp", JSON.encode!(message))
        |> json_response(400)

      assert response["error"]["code"] == -32_020
      assert response["error"]["message"] =~ @version
    end
  end

  describe "methods" do
    test "removed and unknown methods are not found", %{conn: conn} do
      for method <- ["ping", "initialize", "logging/setLevel"] do
        response = build_conn() |> post_mcp(MCPMessages.request(1, method)) |> json_response(404)
        assert response["error"]["code"] == -32_601
      end

      assert %{"error" => %{"data" => %{"supported" => [@version]}}} =
               conn |> post_mcp(MCPMessages.request(1, "initialize")) |> json_response(404)
    end

    test "unknown tools and malformed calls are invalid params", %{conn: conn} do
      for params <- [%{"name" => "nope"}, %{"name" => 1}, %{}, %{"name" => "query_logs", "arguments" => 1}] do
        response = build_conn() |> post_mcp(MCPMessages.request(1, "tools/call", params)) |> json_response(400)
        assert response["error"]["code"] == -32_602
      end

      assert conn |> post_mcp(call("query_logs", nil)) |> json_response(400)
    end

    test "subscriptions/listen acknowledges nothing and closes gracefully", %{conn: conn} do
      conn =
        post_mcp(
          conn,
          MCPMessages.request(7, "subscriptions/listen", %{"notifications" => %{"toolsListChanged" => true}})
        )

      assert conn.status == 200
      assert [content_type] = get_resp_header(conn, "content-type")
      assert content_type =~ "text/event-stream"
      assert get_resp_header(conn, "x-accel-buffering") == ["no"]

      [ack, completion] =
        conn.resp_body
        |> String.split("\n\n", trim: true)
        |> Enum.map(fn "data: " <> json -> JSON.decode!(json) end)

      assert ack["method"] == "notifications/subscriptions/acknowledged"
      assert ack["params"]["notifications"] == %{}
      assert ack["params"]["_meta"]["io.modelcontextprotocol/subscriptionId"] == 7
      refute Map.has_key?(ack, "id")

      assert completion["id"] == 7
      assert completion["result"]["resultType"] == "complete"
      assert completion["result"]["_meta"]["io.modelcontextprotocol/subscriptionId"] == 7
    end

    test "subscriptions/listen validates its filter", %{conn: conn} do
      for params <- [
            %{},
            %{"notifications" => []},
            %{"notifications" => %{"toolsListChanged" => "yes"}},
            %{"notifications" => %{"resourceSubscriptions" => [1]}}
          ] do
        response =
          build_conn() |> post_mcp(MCPMessages.request(1, "subscriptions/listen", params)) |> json_response(400)

        assert response["error"]["code"] == -32_602
      end

      assert conn
             |> post_mcp(MCPMessages.request(1, "subscriptions/listen", %{"notifications" => %{"futureFlag" => 1}}))
             |> response(200)
    end
  end

  describe "message framing" do
    test "notifications are accepted with 202 and never executed", %{conn: conn} do
      for message <- [
            %{"jsonrpc" => "2.0", "method" => "notifications/initialized"},
            %{"jsonrpc" => "2.0", "method" => "tools/call", "params" => %{"name" => "query_logs"}}
          ] do
        conn = raw_post(build_conn(), JSON.encode!(message))
        assert conn.status == 202
        assert conn.resp_body == ""
      end

      assert raw_post(conn, JSON.encode!(%{"jsonrpc" => "2.0", "method" => "x", "params" => []})).status == 400
    end

    test "batches, scalars, responses, and bad envelopes are invalid requests", %{conn: conn} do
      bodies = [
        JSON.encode!([MCPMessages.request(1, "tools/list")]),
        "[]",
        "1",
        "null",
        JSON.encode!(%{"jsonrpc" => "2.0", "id" => 1, "result" => %{}}),
        JSON.encode!(%{"jsonrpc" => "1.0", "id" => 1, "method" => "tools/list"}),
        JSON.encode!(%{"jsonrpc" => "2.0", "id" => nil, "method" => "tools/list"}),
        JSON.encode!(%{"jsonrpc" => "2.0", "id" => 1.5, "method" => "tools/list"}),
        JSON.encode!(%{"jsonrpc" => "2.0", "id" => 1, "method" => 1})
      ]

      for body <- bodies do
        response = build_conn() |> raw_post(body) |> json_response(400)
        assert response["error"]["code"] == -32_600
        refute Map.has_key?(response, "id") and is_nil(response["id"])
      end

      # A request that happens to contain a `_json` field is not a batch.
      message = Map.put(MCPMessages.request(1, "tools/list"), "_json", [1])
      assert conn |> post_mcp(message) |> json_response(200)
    end

    test "non-JSON bodies are unsupported media types and never dispatched", %{conn: conn} do
      form =
        URI.encode_query(%{
          "jsonrpc" => "2.0",
          "id" => "1",
          "method" => "tools/call",
          "params[_meta][io.modelcontextprotocol/protocolVersion]" => @version,
          "params[_meta][io.modelcontextprotocol/clientCapabilities][x]" => "y",
          "params[name]" => "query_logs",
          "params[arguments][tenant]" => "acme"
        })

      for content_type <- ["application/x-www-form-urlencoded", "multipart/form-data; boundary=x", "text/plain"] do
        conn =
          build_conn()
          |> put_req_header("mcp-protocol-version", @version)
          |> put_req_header("mcp-method", "tools/call")
          |> put_req_header("mcp-name", "query_logs")
          |> then(&if content_type, do: put_req_header(&1, "content-type", content_type), else: &1)
          |> post("/mcp", form)

        assert conn.status == 415
        assert JSON.decode!(conn.resp_body)["error"]["code"] == -32_600
      end

      # Without a content type at all.
      conn_without_type =
        :post
        |> Plug.Test.conn("/mcp", JSON.encode!(MCPMessages.request(1, "tools/list")))
        |> PulseWeb.Endpoint.call([])

      assert conn_without_type.status == 415

      assert conn
             |> put_req_header("content-type", "application/json; charset=utf-8")
             |> post_mcp(MCPMessages.request(1, "tools/list"))
             |> json_response(200)
    end

    test "an unparseable body is a JSON-RPC parse error", %{conn: conn} do
      for path <- ["/mcp", "/%6dcp"] do
        {400, _headers, body} =
          assert_error_sent(400, fn ->
            conn |> put_req_header("content-type", "application/json") |> post(path, "{not json")
          end)

        assert JSON.decode!(body)["error"]["code"] == -32_700
      end
    end

    test "a _method field in the body cannot override the HTTP method", %{conn: conn} do
      message = Map.put(MCPMessages.request(1, "tools/list"), "_method", "DELETE")
      assert %{"id" => 1, "result" => %{"tools" => _}} = conn |> post_mcp(message) |> json_response(200)
    end

    test "GET and DELETE are not allowed", %{conn: conn} do
      for verb <- [:get, :delete, :put] do
        conn = dispatch(build_conn(), @endpoint, verb, "/mcp", nil)
        assert conn.status == 405
        assert get_resp_header(conn, "allow") == ["POST"]
      end

      assert dispatch(conn, @endpoint, :get, "/mcp", nil) |> get_resp_header("mcp-session-id") == []
    end
  end

  describe "origin" do
    setup do
      Pulse.Runtime.put_env(:pulse, PulseWeb.MCPController, allowed_origins: ["https://Atlas.example.com:443"])
    end

    test "absent and allowed origins pass", %{conn: conn} do
      assert conn |> post_mcp(MCPMessages.request(1, "tools/list")) |> json_response(200)

      for origin <- ["https://atlas.example.com", "HTTPS://ATLAS.EXAMPLE.COM:443"] do
        assert build_conn()
               |> put_req_header("origin", origin)
               |> post_mcp(MCPMessages.request(1, "tools/list"))
               |> json_response(200)
      end
    end

    test "invalid origins are forbidden before parsing or dispatch", %{conn: conn} do
      for origin <- [
            "https://evil.example.com",
            "http://atlas.example.com",
            "https://atlas.example.com:8443",
            "https://atlas.example.com/path",
            "https://user@atlas.example.com",
            "null",
            "not an origin"
          ] do
        conn = build_conn() |> put_req_header("origin", origin) |> raw_post("{not json")
        assert conn.status == 403
        assert JSON.decode!(conn.resp_body)["error"]["code"] == -32_600
      end

      conn =
        conn
        |> Map.update!(
          :req_headers,
          &[{"origin", "https://atlas.example.com"}, {"origin", "https://atlas.example.com"} | &1]
        )
        |> raw_post(JSON.encode!(MCPMessages.request(1, "tools/list")))

      assert conn.status == 403
    end

    test "percent-encoded paths cannot skip the gate", %{conn: conn} do
      for path <- ["/%6dcp", "/m%63p", "/%6D%63%70"] do
        conn =
          build_conn()
          |> put_req_header("origin", "https://evil.example.com")
          |> put_req_header("content-type", "application/json")
          |> post(path, "{not json")

        assert conn.status == 403
      end

      assert conn |> put_req_header("content-type", "text/plain") |> post("/%6dcp", "x") |> response(415)
    end

    test "IPv6 hosts and ports cannot collide", %{conn: conn} do
      Pulse.Runtime.put_env(:pulse, PulseWeb.MCPController, allowed_origins: ["https://[::1]:8443"])

      for origin <- ["https://[::1:8443]", "https://[::1]", "https://[::1]:443"] do
        conn =
          build_conn()
          |> put_req_header("origin", origin)
          |> post_mcp(MCPMessages.request(1, "tools/list"))

        assert conn.status == 403
      end

      assert conn
             |> put_req_header("origin", "https://[::1]:8443")
             |> post_mcp(MCPMessages.request(1, "tools/list"))
             |> json_response(200)
    end

    test "non-ASCII and control bytes in Origin are rejected, not crashes", %{conn: conn} do
      for origin <- [<<255>>, "https://atlas.example.com\u00e9", "https://atlas.example.com\t", ""] do
        conn =
          build_conn()
          |> Map.update!(:req_headers, &[{"origin", origin} | &1])
          |> raw_post(JSON.encode!(MCPMessages.request(1, "tools/list")))

        assert conn.status == 403
      end

      assert conn
             |> Map.update!(:req_headers, &[{"origin", "https://atlas.example.com"} | &1])
             |> post_mcp(MCPMessages.request(1, "tools/list"))
             |> json_response(200)
    end

    test "the origin check is scoped to /mcp", %{conn: conn} do
      conn = conn |> put_req_header("origin", "https://evil.example.com") |> get("/loki/api/v1/labels")
      refute conn.status == 403
    end
  end

  defp call(name, arguments) do
    params =
      if is_nil(arguments), do: %{"name" => name, "arguments" => nil}, else: %{"name" => name, "arguments" => arguments}

    MCPMessages.request(1, "tools/call", params)
  end

  defp post_mcp(conn, message, opts \\ []) do
    omit = Keyword.get(opts, :omit)

    body_version =
      case message do
        %{"params" => %{"_meta" => %{@meta_version => version}}} when is_binary(version) -> version
        _ -> @version
      end

    headers = [
      {"mcp-protocol-version", Keyword.get(opts, :version, body_version)},
      {"mcp-method", Keyword.get(opts, :method, message["method"])},
      {"mcp-name", Keyword.get(opts, :name, message["params"]["name"])}
    ]

    headers
    |> Enum.reject(fn {name, value} -> name == omit or not is_binary(value) end)
    |> Enum.reduce(conn, fn {name, value}, conn -> put_req_header(conn, name, value) end)
    |> put_req_header("accept", "application/json, text/event-stream")
    |> raw_post(JSON.encode!(message))
  end

  defp raw_post(conn, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post("/mcp", body)
  end
end
