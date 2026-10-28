defmodule AtlasWeb.GitHubEventsControllerTest do
  use AtlasWeb.ConnCase, async: true
  use Oban.Testing, repo: Atlas.Repo

  alias Atlas.Integrations
  alias Atlas.Product.Workers.IngestGitHubEvent

  defp create_app(attrs \\ %{}) do
    defaults = %{
      name: "Test App",
      webhook_secret: "test_webhook_secret",
      app_id: "123",
      private_key: "-----BEGIN RSA PRIVATE KEY-----\nfake\n-----END RSA PRIVATE KEY-----",
      installation_id: "456"
    }

    {:ok, app} = Integrations.create_github_app(Map.merge(defaults, attrs))

    {:ok, _} = Integrations.add_github_repository(app, %{owner: "tuist", repo: "atlas"})
    app
  end

  defp sign_payload(body, secret) do
    "sha256=" <>
      (:crypto.mac(:hmac, :sha256, secret, body) |> Base.encode16(case: :lower))
  end

  defp post_signed(conn, app, event_type, payload) do
    body = Jason.encode!(payload)
    signature = sign_payload(body, app.webhook_secret)

    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-github-event", event_type)
    |> put_req_header("x-hub-signature-256", signature)
    |> post(~p"/api/github/events", body)
  end

  describe "POST /api/github/events" do
    test "returns 200 with valid signature for an issue event", %{conn: conn} do
      app = create_app()

      payload = %{
        "action" => "opened",
        "repository" => %{"full_name" => "tuist/atlas"},
        "issue" => %{
          "title" => "Test issue",
          "body" => "Test body",
          "number" => 1,
          "html_url" => "https://github.com/tuist/atlas/issues/1",
          "created_at" => "2026-03-06T12:00:00Z",
          "user" => %{"login" => "testuser"}
        }
      }

      conn = post_signed(conn, app, "issues", payload)
      assert json_response(conn, 200) == %{"ok" => true}

      assert_enqueued(
        worker: IngestGitHubEvent,
        args: %{"event_type" => "issues", "github_app_id" => app.id}
      )
    end

    test "accepts a signed event whose installation matches no configured app", %{conn: conn} do
      _first = create_app()

      second =
        create_app(%{
          name: "Second App",
          webhook_secret: "second_webhook_secret",
          app_id: "789",
          installation_id: "1011"
        })

      payload = %{
        "action" => "opened",
        "repository" => %{"full_name" => "tuist/atlas"},
        "issue" => %{
          "title" => "Repository-level webhook",
          "body" => "This payload carries no installation.",
          "number" => 7,
          "html_url" => "https://github.com/tuist/atlas/issues/7",
          "created_at" => "2026-03-06T12:00:00Z",
          "user" => %{"login" => "testuser"}
        }
      }

      conn = post_signed(conn, second, "issues", payload)
      assert json_response(conn, 200) == %{"ok" => true}

      assert_enqueued(
        worker: IngestGitHubEvent,
        args: %{"event_type" => "issues", "github_app_id" => second.id}
      )
    end

    test "returns 401 with invalid signature", %{conn: conn} do
      _app = create_app()

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-github-event", "issues")
        |> put_req_header("x-hub-signature-256", "sha256=invalid")
        |> post(~p"/api/github/events", Jason.encode!(%{"action" => "opened"}))

      assert json_response(conn, 401) == %{"error" => "invalid signature"}
    end

    test "returns 401 when no app is configured", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-github-event", "issues")
        |> put_req_header("x-hub-signature-256", "sha256=something")
        |> post(~p"/api/github/events", Jason.encode!(%{"action" => "opened"}))

      assert json_response(conn, 401) == %{"error" => "not configured"}
    end
  end
end
