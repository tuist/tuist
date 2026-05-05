defmodule TuistWeb.Webhooks.GitHubControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.VCS
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.VCSFixtures
  alias TuistWeb.Webhooks.GitHubController

  describe "handle/2" do
    test "returns ok for unknown event types", %{conn: conn} do
      # Given
      conn = put_req_header(conn, "x-github-event", "push")

      # When
      result = GitHubController.handle(conn, %{})

      # Then
      assert result.status == 200
    end

    test "handles installation deleted event successfully", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()
      account = user.account
      installation_id = "12345"

      github_app_installation =
        VCSFixtures.github_app_installation_fixture(
          account_id: account.id,
          installation_id: installation_id
        )

      conn = put_req_header(conn, "x-github-event", "installation")

      expect(VCS, :get_github_app_installation_by_installation_id, fn ^installation_id ->
        {:ok, github_app_installation}
      end)

      expect(VCS, :delete_github_app_installation, fn ^github_app_installation ->
        {:ok, github_app_installation}
      end)

      # When
      result =
        GitHubController.handle(conn, %{
          "action" => "deleted",
          "installation" => %{"id" => installation_id}
        })

      # Then
      assert result.status == 200
    end

    test "handles installation deleted event when installation not found", %{conn: conn} do
      # Given
      installation_id = "99999"
      conn = put_req_header(conn, "x-github-event", "installation")

      expect(VCS, :get_github_app_installation_by_installation_id, fn ^installation_id ->
        {:error, :not_found}
      end)

      # When
      result =
        GitHubController.handle(conn, %{
          "action" => "deleted",
          "installation" => %{"id" => installation_id}
        })

      # Then
      assert result.status == 200
    end

    test "handles installation created event successfully", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()
      account = user.account
      installation_id = "67890"
      html_url = "https://github.com/organizations/tuist/settings/installations/67890"

      github_app_installation =
        VCSFixtures.github_app_installation_fixture(
          account_id: account.id,
          installation_id: installation_id
        )

      conn = put_req_header(conn, "x-github-event", "installation")

      expect(VCS, :get_github_app_installation_by_installation_id, fn ^installation_id ->
        {:ok, github_app_installation}
      end)

      expect(VCS, :update_github_app_installation, fn ^github_app_installation, %{html_url: ^html_url} ->
        {:ok, %{github_app_installation | html_url: html_url}}
      end)

      # When
      result =
        GitHubController.handle(conn, %{
          "action" => "created",
          "installation" => %{"id" => installation_id, "html_url" => html_url}
        })

      # Then
      assert result.status == 200
    end

    test "handles installation created event when installation not found after retries",
         %{
           conn: conn
         } do
      # Given
      installation_id = "88888"
      html_url = "https://github.com/organizations/tuist/settings/installations/88888"
      conn = put_req_header(conn, "x-github-event", "installation")

      # Expect 3 attempts (original + 2 retries)
      expect(VCS, :get_github_app_installation_by_installation_id, 3, fn ^installation_id ->
        {:error, :not_found}
      end)

      # When
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          result =
            GitHubController.handle(conn, %{
              "action" => "created",
              "installation" => %{"id" => installation_id, "html_url" => html_url}
            })

          # Then
          assert result.status == 200
        end)

      # Verify final error was logged after all retries exhausted
      assert log =~ "installation_id=#{installation_id}"
      assert log =~ "not found after retries"
    end

    test "handles installation created event with successful retry",
         %{
           conn: conn
         } do
      # Given
      user = AccountsFixtures.user_fixture()
      account = user.account
      installation_id = "99999"
      html_url = "https://github.com/organizations/tuist/settings/installations/99999"

      github_app_installation =
        VCSFixtures.github_app_installation_fixture(
          account_id: account.id,
          installation_id: installation_id
        )

      conn = put_req_header(conn, "x-github-event", "installation")

      # Simulate race condition: first call returns not found, but installation
      # is created by the time of the retry
      call_count = :counters.new(1, [])

      expect(VCS, :get_github_app_installation_by_installation_id, 2, fn ^installation_id ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)

        if count == 0 do
          {:error, :not_found}
        else
          {:ok, github_app_installation}
        end
      end)

      expect(VCS, :update_github_app_installation, fn ^github_app_installation, %{html_url: ^html_url} ->
        {:ok, %{github_app_installation | html_url: html_url}}
      end)

      # When
      result =
        GitHubController.handle(conn, %{
          "action" => "created",
          "installation" => %{"id" => installation_id, "html_url" => html_url}
        })

      # Then - successfully handled after retry
      assert result.status == 200
    end

    test "returns ok for installation events with non-deleted actions", %{conn: conn} do
      # Given
      conn = put_req_header(conn, "x-github-event", "installation")

      # When
      result =
        GitHubController.handle(conn, %{
          "action" => "suspend",
          "installation" => %{"id" => "12345"}
        })

      # Then
      assert result.status == 200
    end
  end

  describe "handle/2 check_run events" do
    test "updates check run to success on accept action", %{conn: conn} do
      conn = put_req_header(conn, "x-github-event", "check_run")

      expect(VCS, :get_github_app_installation_by_installation_id, fn installation_id ->
        assert installation_id == "12345"
        {:ok, %{installation_id: "12345"}}
      end)

      expect(VCS, :update_check_run, fn params ->
        assert params.check_run_id == 42
        assert params.conclusion == "success"
        assert params.installation.installation_id == "12345"
        assert params.repository_full_handle == "org/repo"
        assert params.output.title == "Bundle size increase accepted"
        {:ok, %{"id" => 42}}
      end)

      result =
        GitHubController.handle(conn, %{
          "action" => "requested_action",
          "check_run" => %{"id" => 42, "name" => "tuist/bundle-size"},
          "requested_action" => %{"identifier" => "accept_bundle_size"},
          "installation" => %{"id" => 12_345},
          "repository" => %{"full_name" => "org/repo"}
        })

      assert result.status == 200
    end

    test "ignores check_run events for unknown installations", %{conn: conn} do
      conn = put_req_header(conn, "x-github-event", "check_run")

      expect(VCS, :get_github_app_installation_by_installation_id, fn _installation_id ->
        {:error, :not_found}
      end)

      reject(VCS, :update_check_run, 1)

      result =
        GitHubController.handle(conn, %{
          "action" => "requested_action",
          "check_run" => %{"id" => 42, "name" => "tuist/bundle-size"},
          "requested_action" => %{"identifier" => "accept_bundle_size"},
          "installation" => %{"id" => 99_999},
          "repository" => %{"full_name" => "org/repo"}
        })

      assert result.status == 200
    end

    test "ignores check_run events for other check names", %{conn: conn} do
      conn = put_req_header(conn, "x-github-event", "check_run")

      reject(VCS, :update_check_run, 1)

      result =
        GitHubController.handle(conn, %{
          "action" => "requested_action",
          "check_run" => %{"id" => 42, "name" => "other-check"},
          "requested_action" => %{"identifier" => "accept_bundle_size"},
          "installation" => %{"id" => 12_345},
          "repository" => %{"full_name" => "org/repo"}
        })

      assert result.status == 200
    end

    test "ignores check_run events for other actions", %{conn: conn} do
      conn = put_req_header(conn, "x-github-event", "check_run")

      reject(VCS, :update_check_run, 1)

      result =
        GitHubController.handle(conn, %{
          "action" => "completed",
          "check_run" => %{"id" => 42, "name" => "tuist/bundle-size"}
        })

      assert result.status == 200
    end
  end

  describe "resolve_webhook_secret/1" do
    test "returns the per-installation secret keyed by installation_id", %{conn: conn} do
      account = AccountsFixtures.user_fixture(preload: [:account]).account

      installation =
        VCSFixtures.github_app_installation_fixture(
          account_id: account.id,
          installation_id: "inst-1",
          client_url: "https://github.example.com",
          app_id: "555",
          app_slug: "tuist-on-ghes",
          client_id: "Iv1.x",
          client_secret: "csec",
          private_key: "-----BEGIN RSA PRIVATE KEY-----\nfake\n-----END RSA PRIVATE KEY-----",
          webhook_secret: "row-webhook-secret"
        )

      body = %{"installation" => %{"id" => installation.installation_id}}
      conn = %{conn | body_params: body}

      assert GitHubController.resolve_webhook_secret(conn) == "row-webhook-secret"
    end

    test "falls back to matching by app_id when installation_id is missing on the row", %{conn: conn} do
      # Simulates the race: GHES delivers installation.created before
      # the redirect-driven /integrations/github/setup callback has
      # filled installation_id on the manifest-flow row.
      account = AccountsFixtures.user_fixture(preload: [:account]).account

      VCSFixtures.github_app_installation_fixture(
        account_id: account.id,
        installation_id: nil,
        client_url: "https://github.example.com",
        app_id: "555",
        app_slug: "tuist-on-ghes",
        client_id: "Iv1.x",
        client_secret: "csec",
        private_key: "-----BEGIN RSA PRIVATE KEY-----\nfake\n-----END RSA PRIVATE KEY-----",
        webhook_secret: "row-webhook-secret"
      )

      body = %{"installation" => %{"id" => 999, "app_id" => 555}}
      conn = %{conn | body_params: body}

      assert GitHubController.resolve_webhook_secret(conn) == "row-webhook-secret"
    end

    test "falls back to matching by the X-GitHub-Hook-Installation-Target-ID header", %{conn: conn} do
      account = AccountsFixtures.user_fixture(preload: [:account]).account

      VCSFixtures.github_app_installation_fixture(
        account_id: account.id,
        installation_id: nil,
        client_url: "https://github.example.com",
        app_id: "777",
        app_slug: "tuist-on-ghes",
        client_id: "Iv1.x",
        client_secret: "csec",
        private_key: "-----BEGIN RSA PRIVATE KEY-----\nfake\n-----END RSA PRIVATE KEY-----",
        webhook_secret: "header-webhook-secret"
      )

      conn =
        conn
        |> put_req_header("x-github-hook-installation-target-id", "777")
        |> Map.put(:body_params, %{"installation" => %{"id" => 999}})

      assert GitHubController.resolve_webhook_secret(conn) == "header-webhook-secret"
    end

    test "falls back to the env-var secret when no row matches", %{conn: conn} do
      stub(Tuist.Environment, :github_app_webhook_secret, fn -> "env-secret" end)

      conn = %{conn | body_params: %{"installation" => %{"id" => 4242}}}

      assert GitHubController.resolve_webhook_secret(conn) == "env-secret"
    end
  end
end
