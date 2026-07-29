defmodule TuistWeb.WellKnownControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Environment
  alias TuistWeb.AgentSkillsDiscovery

  setup do
    stub(Environment, :app_url, fn -> "https://tuist.dev" end)

    stub(Environment, :app_url, fn options ->
      if Keyword.get(options, :route_type) == :app do
        "http://www.example.com"
      else
        "https://tuist.dev#{Keyword.get(options, :path, "")}"
      end
    end)

    :ok
  end

  describe "GET /.well-known/api-catalog" do
    test "returns a linkset API catalog", %{conn: conn} do
      conn =
        conn
        |> put_req_header("accept", "application/linkset+json")
        |> get("/.well-known/api-catalog")

      assert response(conn, 200)

      assert get_resp_header(conn, "content-type") == [
               ~s(application/linkset+json; profile="https://www.rfc-editor.org/info/rfc9727")
             ]

      assert get_resp_header(conn, "link") == [
               ~s(</.well-known/api-catalog>; rel="api-catalog"; type="application/linkset+json"; profile="https://www.rfc-editor.org/info/rfc9727")
             ]

      assert JSON.decode!(conn.resp_body) == %{
               "linkset" => [
                 %{
                   "anchor" => "http://www.example.com/api",
                   "service-desc" => [
                     %{
                       "href" => "http://www.example.com/api/spec",
                       "type" => "application/json"
                     }
                   ],
                   "service-doc" => [
                     %{
                       "href" => "http://www.example.com/api/docs",
                       "type" => "text/html"
                     }
                   ],
                   "status" => [
                     %{
                       "href" => "http://www.example.com/ready"
                     }
                   ]
                 }
               ]
             }
    end

    test "returns the API catalog without requiring an explicit linkset accept header", %{conn: conn} do
      conn = get(conn, "/.well-known/api-catalog")

      assert response(conn, 200)

      assert get_resp_header(conn, "content-type") == [
               ~s(application/linkset+json; profile="https://www.rfc-editor.org/info/rfc9727")
             ]

      assert JSON.decode!(conn.resp_body) == %{
               "linkset" => [
                 %{
                   "anchor" => "http://www.example.com/api",
                   "service-desc" => [
                     %{
                       "href" => "http://www.example.com/api/spec",
                       "type" => "application/json"
                     }
                   ],
                   "service-doc" => [
                     %{
                       "href" => "http://www.example.com/api/docs",
                       "type" => "text/html"
                     }
                   ],
                   "status" => [
                     %{
                       "href" => "http://www.example.com/ready"
                     }
                   ]
                 }
               ]
             }
    end

    test "includes an api-catalog link header on HEAD requests", %{conn: conn} do
      conn = head(conn, "/.well-known/api-catalog")

      assert response(conn, 200) == ""

      assert get_resp_header(conn, "link") == [
               ~s(</.well-known/api-catalog>; rel="api-catalog"; type="application/linkset+json"; profile="https://www.rfc-editor.org/info/rfc9727")
             ]
    end
  end

  describe "GET /.well-known/agent-skills/index.json" do
    test "returns the agent skills discovery index", %{conn: conn} do
      conn = get(conn, "/.well-known/agent-skills/index.json")

      assert json_response(conn, 200) == AgentSkillsDiscovery.index()
    end
  end

  describe "GET /.well-known/registry.json" do
    test "advertises the swift ecosystem and derives its login path", %{conn: conn} do
      stub(Tuist.Registry, :url, fn -> "https://registry.tuist.dev/api/registry/swift" end)

      conn = get(conn, "/.well-known/registry.json")

      assert json_response(conn, 200) == %{
               "ecosystems" => %{
                 "swift" => %{
                   "url" => "https://registry.tuist.dev/api/registry/swift",
                   "loginAPIPath" => "/api/registry/swift/login"
                 }
               }
             }
    end

    test "serves JSON to clients that send an application/json Accept header", %{conn: conn} do
      stub(Tuist.Registry, :url, fn -> "https://registry.tuist.dev/swift" end)

      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> get("/.well-known/registry.json")

      assert json_response(conn, 200) == %{
               "ecosystems" => %{
                 "swift" => %{
                   "url" => "https://registry.tuist.dev/swift",
                   "loginAPIPath" => "/swift/login"
                 }
               }
             }
    end

    test "404s when the deployment exposes no registry", %{conn: conn} do
      stub(Tuist.Registry, :url, fn -> nil end)

      conn = get(conn, "/.well-known/registry.json")

      assert response(conn, 404) == ""
    end
  end

  describe "GET /.well-known/mcp/server-card.json" do
    test "returns the MCP server card", %{conn: conn} do
      conn = get(conn, "/.well-known/mcp/server-card.json")

      response = json_response(conn, 200)
      server = Tuist.MCP.Server.server()

      assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]
      assert get_resp_header(conn, "access-control-allow-origin") == ["*"]
      assert get_resp_header(conn, "cache-control") == ["public, max-age=3600"]
      refute Map.has_key?(response, "$schema")
      assert response["version"] == "1.0"
      assert response["protocolVersion"] == "2025-06-18"
      assert response["serverInfo"]["name"] == server.name
      assert response["serverInfo"]["version"] == server.version
      assert response["serverInfo"]["title"] == "Tuist"
      assert response["transport"]["type"] == "streamable-http"
      assert response["transport"]["endpoint"] == "/mcp"
      assert response["capabilities"]["tools"] == %{"listChanged" => true}
      assert response["capabilities"]["prompts"] == %{"listChanged" => true}

      assert response["authentication"] == %{
               "required" => true,
               "schemes" => ["bearer", "oauth2"]
             }

      assert response["instructions"] == server.instructions
      assert response["tools"] == ["dynamic"]
      assert response["prompts"] == ["dynamic"]
    end
  end

  describe "GET /.well-known/openai-apps-challenge" do
    test "returns the OpenAI Apps challenge token for Tuist-hosted deployments", %{conn: conn} do
      expect(Environment, :tuist_hosted?, fn -> true end)

      conn = get(conn, "/.well-known/openai-apps-challenge")

      assert response(conn, 200) == "YoBqoSMoA-RuEX8RMuCKrLnPCXDYUsYtKg-yjFBHmDQ"
      assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
    end

    test "returns the OpenAI Apps challenge token when the Accept header is text/plain", %{conn: conn} do
      expect(Environment, :tuist_hosted?, fn -> true end)

      conn =
        conn
        |> put_req_header("accept", "text/plain")
        |> get("/.well-known/openai-apps-challenge")

      assert response(conn, 200) == "YoBqoSMoA-RuEX8RMuCKrLnPCXDYUsYtKg-yjFBHmDQ"
      assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
    end

    test "returns not found for on-premise deployments", %{conn: conn} do
      expect(Environment, :tuist_hosted?, fn -> false end)

      conn = get(conn, "/.well-known/openai-apps-challenge")

      assert response(conn, 404) == ""
    end
  end

  describe "GET /.well-known/oauth-authorization-server" do
    test "returns OAuth authorization server metadata", %{conn: conn} do
      conn = get(conn, "/.well-known/oauth-authorization-server")

      response = json_response(conn, 200)

      assert response["issuer"] == "http://www.example.com"
      assert response["authorization_endpoint"] == "http://www.example.com/oauth2/authorize"
      assert response["token_endpoint"] == "http://www.example.com/oauth2/token"
      assert response["revocation_endpoint"] == "http://www.example.com/oauth2/revoke"
      assert response["jwks_uri"] == "http://www.example.com/.well-known/jwks.json"
      assert response["introspection_endpoint"] == "http://www.example.com/oauth2/introspect"
      assert response["registration_endpoint"] == "http://www.example.com/oauth2/register"
      assert response["scopes_supported"] == ["mcp"]

      assert response["agent_auth"] == %{
               "skill" => "http://www.example.com/auth.md",
               "identity_endpoint" => "http://www.example.com/agent/identity",
               "claim_endpoint" => "http://www.example.com/agent/identity/claim",
               "events_endpoint" => "http://www.example.com/agent/event/notify",
               "identity_types_supported" => ["anonymous", "identity_assertion", "service_auth"],
               "identity_assertion" => %{
                 "assertion_types_supported" => ["urn:ietf:params:oauth:token-type:id-jag"]
               },
               "events_supported" => ["https://schemas.workos.com/events/agent/auth/identity/assertion/revoked"],
               "compatibility" => %{
                 "legacy_registration_endpoint" => "http://www.example.com/agent/auth",
                 "legacy_claim_endpoint" => "http://www.example.com/agent/auth/claim"
               }
             }
    end

    test "keeps the configured canonical origin behind a forwarding proxy", %{conn: conn} do
      conn =
        conn
        |> put_req_header("x-forwarded-proto", "https")
        |> put_req_header("x-forwarded-host", "self-hosted.example.com")
        |> put_req_header("x-forwarded-port", "443")
        |> get("/.well-known/oauth-authorization-server")

      response = json_response(conn, 200)

      assert response["issuer"] == "http://www.example.com"
      assert response["authorization_endpoint"] == "http://www.example.com/oauth2/authorize"
      assert response["token_endpoint"] == "http://www.example.com/oauth2/token"
      assert response["introspection_endpoint"] == "http://www.example.com/oauth2/introspect"
      assert response["registration_endpoint"] == "http://www.example.com/oauth2/register"
      assert response["agent_auth"]["skill"] == "http://www.example.com/auth.md"
      assert response["agent_auth"]["identity_endpoint"] == "http://www.example.com/agent/identity"
      assert response["agent_auth"]["claim_endpoint"] == "http://www.example.com/agent/identity/claim"
      assert response["agent_auth"]["events_endpoint"] == "http://www.example.com/agent/event/notify"
    end
  end

  describe "GET /.well-known/oauth-protected-resource" do
    test "returns host-level protected resource metadata", %{conn: conn} do
      conn = get(conn, "/.well-known/oauth-protected-resource")

      response = json_response(conn, 200)

      assert response["resource"] == "http://www.example.com"
      assert response["resource_name"] == "Tuist"
      assert response["authorization_servers"] == ["http://www.example.com"]
      assert response["bearer_methods_supported"] == ["header"]
      assert response["scopes_supported"] == ["mcp"]
      assert response["agent_auth"]["skill"] == "http://www.example.com/auth.md"
      assert response["agent_auth"]["identity_endpoint"] == "http://www.example.com/agent/identity"

      assert response["agent_auth"]["identity_assertion"]["assertion_types_supported"] == [
               "urn:ietf:params:oauth:token-type:id-jag"
             ]

      assert response["resource_documentation"] ==
               "http://www.example.com/en/docs/guides/features/agentic-coding/mcp"
    end
  end

  describe "GET /.well-known/oauth-protected-resource/mcp" do
    test "returns MCP protected resource metadata", %{conn: conn} do
      conn = get(conn, "/.well-known/oauth-protected-resource/mcp")

      response = json_response(conn, 200)

      assert response["resource"] == "http://www.example.com/mcp"
      assert response["resource_name"] == "Tuist MCP"
      assert response["authorization_servers"] == ["http://www.example.com"]
      assert response["bearer_methods_supported"] == ["header"]
      assert response["scopes_supported"] == ["mcp"]
      assert response["agent_auth"]["claim_endpoint"] == "http://www.example.com/agent/identity/claim"

      assert response["resource_documentation"] ==
               "http://www.example.com/en/docs/guides/features/agentic-coding/mcp"
    end

    test "keeps the configured canonical resource when reached through an alias", %{conn: conn} do
      conn =
        conn
        |> Map.put(:host, "custom.tuist.dev")
        |> Map.put(:port, 8443)
        |> get("/.well-known/oauth-protected-resource/mcp")

      response = json_response(conn, 200)

      assert response["resource"] == "http://www.example.com/mcp"
      assert response["resource_name"] == "Tuist MCP"
      assert response["authorization_servers"] == ["http://www.example.com"]
    end

    test "returns not found for unsupported protected resources", %{conn: conn} do
      conn = get(conn, "/.well-known/oauth-protected-resource/api")

      assert json_response(conn, 404) == %{"error" => "not_found"}
    end
  end

  describe "GET /.well-known/apple-app-site-association" do
    test "returns the apple app site association JSON", %{conn: conn} do
      conn = get(conn, "/.well-known/apple-app-site-association")

      assert json_response(conn, 200) == %{
               "applinks" => %{
                 "apps" => [],
                 "details" => [
                   %{
                     "appID" => "U6LC622NKF.dev.tuist.app",
                     "paths" => ["/*/*/previews/*"]
                   }
                 ]
               }
             }

      assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]
    end
  end

  describe "GET /.well-known/assetlinks.json" do
    test "returns Android asset links with release fingerprint", %{conn: conn} do
      conn = get(conn, "/.well-known/assetlinks.json")

      response = json_response(conn, 200)

      assert [link] = response
      assert link["relation"] == ["delegate_permission/common.handle_all_urls"]
      assert link["target"]["namespace"] == "android_app"
      assert link["target"]["package_name"] == "dev.tuist.app"
      assert is_list(link["target"]["sha256_cert_fingerprints"])

      assert "D9:94:6C:7F:C9:CA:86:91:38:26:7C:21:BC:C9:92:10:91:DB:A7:31:C5:AE:8E:05:30:89:5B:11:94:CF:E2:2D" in link[
               "target"
             ]["sha256_cert_fingerprints"]
    end
  end
end
