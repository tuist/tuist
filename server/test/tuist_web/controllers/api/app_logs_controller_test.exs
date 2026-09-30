defmodule TuistWeb.API.AppLogsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.AccountsFixtures
  import TuistTestSupport.Fixtures.ProjectsFixtures

  alias Tuist.Accounts
  alias Tuist.Environment
  alias TuistWeb.RateLimit

  @receiver_url "http://alloy.test:3100/loki/api/v1/push"

  defp body(entries) do
    %{
      app: %{platform: "ios", version: "0.25.7", build: "1790000000", os_version: "Version 26.0"},
      entries: entries
    }
  end

  defp entry(attrs \\ %{}) do
    Map.merge(
      %{
        timestamp: DateTime.to_iso8601(DateTime.utc_now()),
        level: "notice",
        source: "TuistAuthentication",
        message: "Authentication state updated to logged out",
        launch_id: "8f5e3f5e-6f6a-4f53-9f3b-2f0f2b7f7a10"
      },
      attrs
    )
  end

  describe "POST /api/app/logs" do
    setup [:register_and_log_in_user]

    test "forwards redacted lines attributed to the authenticated user", %{conn: conn, user: user} do
      user = Tuist.Repo.preload(user, :account)
      organization = organization_fixture()
      Accounts.add_user_to_organization(user, organization)
      stub(Environment, :app_logs_receiver_url, fn -> @receiver_url end)

      expect(Req, :post, fn @receiver_url, opts ->
        [stream] = opts[:json].streams
        assert stream.stream == %{service_name: "tuist-app", environment: "test", platform: "ios"}

        [[timestamp, line]] = stream.values
        assert String.to_integer(timestamp) > 0

        line = JSON.decode!(line)
        assert line["message"] == "Signed in as [redacted]"
        assert line["user_id"] == user.id
        assert line["user_handle"] == user.account.name
        assert line["organization_handles"] == organization.account.name
        assert line["app_version"] == "0.25.7"
        assert line["level"] == "notice"
        assert line["launch_id"] == "8f5e3f5e-6f6a-4f53-9f3b-2f0f2b7f7a10"

        {:ok, %Req.Response{status: 204}}
      end)

      conn =
        conn
        |> assign(:current_user, user)
        |> put_req_header("content-type", "application/json")
        |> post("/api/app/logs", body([entry(%{message: "Signed in as someone@example.com"})]))

      assert response(conn, :accepted) == ""
    end

    test "drops lines older than Loki accepts and skips the push when none remain", %{conn: conn, user: user} do
      stub(Environment, :app_logs_receiver_url, fn -> @receiver_url end)
      reject(&Req.post/2)
      old = DateTime.utc_now() |> DateTime.add(-4, :day) |> DateTime.to_iso8601()

      conn =
        conn
        |> assign(:current_user, user)
        |> put_req_header("content-type", "application/json")
        |> post("/api/app/logs", body([entry(%{timestamp: old})]))

      assert response(conn, :accepted) == ""
    end

    test "accepts and discards logs when no receiver is configured", %{conn: conn, user: user} do
      stub(Environment, :app_logs_receiver_url, fn -> nil end)
      reject(&Req.post/2)

      conn =
        conn
        |> assign(:current_user, user)
        |> put_req_header("content-type", "application/json")
        |> post("/api/app/logs", body([entry()]))

      assert response(conn, :accepted) == ""
    end

    test "returns service unavailable when the receiver rejects the push", %{conn: conn, user: user} do
      stub(Environment, :app_logs_receiver_url, fn -> @receiver_url end)
      stub(Req, :post, fn _url, _opts -> {:ok, %Req.Response{status: 500}} end)

      conn =
        conn
        |> assign(:current_user, user)
        |> put_req_header("content-type", "application/json")
        |> post("/api/app/logs", body([entry()]))

      assert json_response(conn, :service_unavailable) == %{"message" => "The logs could not be forwarded."}
    end

    test "returns too many requests when the user exceeds the upload rate", %{conn: conn, user: user} do
      stub(Environment, :app_logs_receiver_url, fn -> @receiver_url end)
      stub(RateLimit, :hit, fn _key, _opts -> {:deny, 30} end)
      reject(&Req.post/2)

      conn =
        conn
        |> assign(:current_user, user)
        |> put_req_header("content-type", "application/json")
        |> post("/api/app/logs", body([entry()]))

      assert json_response(conn, :too_many_requests)
    end

    test "rejects messages longer than the schema allows", %{conn: conn, user: user} do
      reject(&Req.post/2)

      conn =
        conn
        |> assign(:current_user, user)
        |> put_req_header("content-type", "application/json")
        |> post("/api/app/logs", body([entry(%{message: String.duplicate("a", 8193)})]))

      assert json_response(conn, :bad_request)
    end

    test "forbids project tokens", %{conn: conn} do
      project = project_fixture()
      reject(&Req.post/2)

      conn =
        conn
        |> assign(:current_project, project)
        |> put_req_header("content-type", "application/json")
        |> post("/api/app/logs", body([entry()]))

      assert json_response(conn, :forbidden) == %{"message" => "Only users can upload app logs."}
    end
  end
end
