defmodule TuistWeb.Webhooks.GitHubControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Runners.Workers.DispatchWorker
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

    test "deletes the github.com row on uninstall when GitHub sends the App ID via X-GitHub-Hook-Installation-Target-ID",
         %{conn: conn} do
      # Regression: github.com installations leave `app_id` NULL on the
      # row, so a naive `app_id = ?` filter on the lookup would miss
      # the row and the uninstall webhook would 200 OK without actually
      # deleting it (the symptom the user hit on staging). The fix is
      # to route github.com webhooks (App ID matches the env var) by
      # `client_url='https://github.com'` instead.
      user = AccountsFixtures.user_fixture()
      installation_id = "gh-com-12345"
      app_id = "777"

      stub(Tuist.Environment, :github_app_id, fn -> app_id end)

      installation =
        VCSFixtures.github_app_installation_fixture(
          account_id: user.account.id,
          installation_id: installation_id,
          client_url: "https://github.com"
        )

      conn =
        conn
        |> put_req_header("x-github-event", "installation")
        |> put_req_header("x-github-hook-installation-target-id", app_id)

      expect(VCS, :get_github_app_installation_by_installation_id, fn ^installation_id, opts ->
        assert Keyword.fetch!(opts, :client_url) == "https://github.com"
        refute Keyword.has_key?(opts, :app_id)
        {:ok, installation}
      end)

      expect(VCS, :delete_github_app_installation, fn ^installation ->
        {:ok, installation}
      end)

      result =
        GitHubController.handle(conn, %{
          "action" => "deleted",
          "installation" => %{"id" => installation_id}
        })

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

    test "fills installation_id on a pending GHES row when installation.created arrives before the setup callback (manifest-flow bootstrap race)",
         %{conn: conn} do
      # Regression: when `resolve_webhook_secret/1` HMAC-matches a row by
      # app_id (its `installation_id` is still nil — the setup callback
      # hasn't fired yet) and stashes it on conn.assigns, the
      # `installation.created` handler must fill the row's
      # `installation_id` from the body. Previously the handler looked
      # the row up by the body's installation_id, missed the pending
      # row entirely, and left it orphaned.
      user = AccountsFixtures.user_fixture()
      installation_id = "fresh-install-id"
      html_url = "https://github.example.com/organizations/x/settings/installations/fresh-install-id"

      pending_row = %Tuist.VCS.GitHubAppInstallation{
        id: "00000000-0000-0000-0000-000000000001",
        account_id: user.account.id,
        installation_id: nil,
        client_url: "https://github.example.com",
        app_id: "999",
        webhook_secret: "wh"
      }

      conn =
        conn
        |> put_req_header("x-github-event", "installation")
        |> Plug.Conn.assign(:github_installation, pending_row)

      expect(VCS, :update_github_app_installation, fn ^pending_row, attrs ->
        assert attrs.installation_id == installation_id
        assert attrs.html_url == html_url
        {:ok, %{pending_row | installation_id: installation_id, html_url: html_url}}
      end)

      result =
        GitHubController.handle(conn, %{
          "action" => "created",
          "installation" => %{"id" => installation_id, "html_url" => html_url}
        })

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

    test "routes the lookup by app_id when the App ID header points at a manifest-flow GHES App",
         %{conn: conn} do
      stub(Tuist.Environment, :github_app_id, fn -> "999" end)

      conn =
        conn
        |> put_req_header("x-github-event", "check_run")
        |> put_req_header("x-github-hook-installation-target-id", "777")

      expect(VCS, :get_github_app_installation_by_installation_id, fn installation_id, opts ->
        assert installation_id == "12345"
        assert Keyword.fetch!(opts, :app_id) == "777"
        {:ok, %{installation_id: "12345"}}
      end)

      expect(VCS, :update_check_run, fn _params -> {:ok, %{"id" => 42}} end)

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

    test "routes the lookup by client_url when the App ID matches the github.com Tuist App so github.com rows (with NULL app_id) still match",
         %{conn: conn} do
      # Regression: github.com installations leave `app_id` NULL on the
      # row (env-var fallback). An `app_id = ?` filter would miss them
      # entirely and post-HMAC handlers (uninstall, html_url update,
      # check_run) would silently no-op. Routing by `client_url` for
      # the github.com Tuist App restores the match.
      stub(Tuist.Environment, :github_app_id, fn -> "777" end)

      conn =
        conn
        |> put_req_header("x-github-event", "check_run")
        |> put_req_header("x-github-hook-installation-target-id", "777")

      expect(VCS, :get_github_app_installation_by_installation_id, fn installation_id, opts ->
        assert installation_id == "12345"
        assert Keyword.fetch!(opts, :client_url) == "https://github.com"
        refute Keyword.has_key?(opts, :app_id)
        {:ok, %{installation_id: "12345"}}
      end)

      expect(VCS, :update_check_run, fn _params -> {:ok, %{"id" => 42}} end)

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
    # Helper: produce the X-Hub-Signature-256 header value GitHub
    # would send for `body` signed with `secret`. The resolver picks
    # the row whose secret reproduces this signature, so any test that
    # wants a per-installation row to win has to compute one.
    defp sign(body, secret) do
      "sha256=" <>
        (:hmac
         |> :crypto.mac(:sha256, secret, body)
         |> Base.encode16(case: :lower))
    end

    defp put_signed_body(conn, raw_body, secret) do
      conn
      |> put_req_header("x-hub-signature-256", sign(raw_body, secret))
      |> Plug.Conn.assign(:raw_body, raw_body)
      |> Map.put(:body_params, JSON.decode!(raw_body))
    end

    test "returns the per-installation secret of the row whose webhook_secret HMACs the body",
         %{conn: conn} do
      account = AccountsFixtures.user_fixture(preload: [:account]).account
      secret = "row-webhook-secret"

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
          webhook_secret: secret
        )

      raw_body = ~s({"installation":{"id":"#{installation.installation_id}"}})
      conn = put_signed_body(conn, raw_body, secret)

      assert {:ok, ^secret, conn} = GitHubController.resolve_webhook_secret(conn)
      assert conn.assigns[:github_installation].id == installation.id
    end

    test "matches by app_id when installation_id on the row is still nil (manifest-flow bootstrap race)",
         %{conn: conn} do
      account = AccountsFixtures.user_fixture(preload: [:account]).account
      secret = "row-webhook-secret"

      VCSFixtures.github_app_installation_fixture(
        account_id: account.id,
        installation_id: nil,
        client_url: "https://github.example.com",
        app_id: "555",
        app_slug: "tuist-on-ghes",
        client_id: "Iv1.x",
        client_secret: "csec",
        private_key: "-----BEGIN RSA PRIVATE KEY-----\nfake\n-----END RSA PRIVATE KEY-----",
        webhook_secret: secret
      )

      raw_body = ~s({"installation":{"id":999,"app_id":555}})
      conn = put_signed_body(conn, raw_body, secret)

      assert {:ok, ^secret, _conn} = GitHubController.resolve_webhook_secret(conn)
    end

    test "matches by the X-GitHub-Hook-Installation-Target-ID header",
         %{conn: conn} do
      account = AccountsFixtures.user_fixture(preload: [:account]).account
      secret = "header-webhook-secret"

      VCSFixtures.github_app_installation_fixture(
        account_id: account.id,
        installation_id: nil,
        client_url: "https://github.example.com",
        app_id: "777",
        app_slug: "tuist-on-ghes",
        client_id: "Iv1.x",
        client_secret: "csec",
        private_key: "-----BEGIN RSA PRIVATE KEY-----\nfake\n-----END RSA PRIVATE KEY-----",
        webhook_secret: secret
      )

      raw_body = ~s({"installation":{"id":999}})

      conn =
        conn
        |> put_req_header("x-github-hook-installation-target-id", "777")
        |> put_signed_body(raw_body, secret)

      assert {:ok, ^secret, _conn} = GitHubController.resolve_webhook_secret(conn)
    end

    test "picks the row whose webhook_secret HMACs the body when two rows share (installation_id, app_id) across hosts (P1 disambiguation)",
         %{conn: conn} do
      # Schema permits this: composite unique index is per host. Two
      # GHES instances can independently assign overlapping numeric IDs
      # to their Apps. Without HMAC-driven row resolution, the lookup
      # picks an arbitrary one (or crashes on multi-result). With it,
      # only the row whose webhook_secret matches GitHub's signature
      # is selected.
      account_a = AccountsFixtures.user_fixture(preload: [:account]).account
      account_b = AccountsFixtures.user_fixture(preload: [:account]).account
      secret_a = "secret-from-ghes-a"
      secret_b = "secret-from-ghes-b"

      _row_a =
        VCSFixtures.github_app_installation_fixture(
          account_id: account_a.id,
          installation_id: "1",
          client_url: "https://ghes-a.example.com",
          app_id: "42",
          app_slug: "tuist",
          client_id: "Iv1.a",
          client_secret: "csec-a",
          private_key: "-----BEGIN RSA PRIVATE KEY-----\nfake-a\n-----END RSA PRIVATE KEY-----",
          webhook_secret: secret_a
        )

      row_b =
        VCSFixtures.github_app_installation_fixture(
          account_id: account_b.id,
          installation_id: "1",
          client_url: "https://ghes-b.example.com",
          app_id: "42",
          app_slug: "tuist",
          client_id: "Iv1.b",
          client_secret: "csec-b",
          private_key: "-----BEGIN RSA PRIVATE KEY-----\nfake-b\n-----END RSA PRIVATE KEY-----",
          webhook_secret: secret_b
        )

      raw_body = ~s({"installation":{"id":"1","app_id":"42"}})
      conn = put_signed_body(conn, raw_body, secret_b)

      assert {:ok, ^secret_b, conn} = GitHubController.resolve_webhook_secret(conn)
      assert conn.assigns[:github_installation].id == row_b.id
    end

    test "falls back to the env-var secret when no row matches", %{conn: conn} do
      stub(Tuist.Environment, :github_app_webhook_secret, fn -> "env-secret" end)

      conn = %{conn | body_params: %{"installation" => %{"id" => 4242}}}

      assert GitHubController.resolve_webhook_secret(conn) == "env-secret"
    end

    test "falls back to the env-var secret for github.com installations whose row carries no per-installation secret",
         %{conn: conn} do
      # Regression: github.com installations land in the DB via the setup
      # callback with `installation_id` populated but no per-installation
      # `webhook_secret` (those columns belong to the manifest flow).
      # Step 1 of resolve_webhook_secret/1 finds the row but its secret is
      # nil; we must fall through to the env var rather than authenticate
      # the webhook with `nil` (which would either crash HMAC or, worse,
      # let unsigned traffic through).
      stub(Tuist.Environment, :github_app_webhook_secret, fn -> "github-com-env-secret" end)

      account = AccountsFixtures.user_fixture(preload: [:account]).account

      VCSFixtures.github_app_installation_fixture(
        account_id: account.id,
        installation_id: "gh-com-12345",
        client_url: "https://github.com"
      )

      conn = %{conn | body_params: %{"installation" => %{"id" => "gh-com-12345"}}}

      assert GitHubController.resolve_webhook_secret(conn) == "github-com-env-secret"
    end
  end

  describe "handle/2 workflow_job" do
    test "200s immediately and enqueues a DispatchWorker job with the payload + GUID", %{conn: conn} do
      installation_id = System.unique_integer([:positive])
      delivery_guid = "deadbeef-0000-1111-2222-333344445555"

      conn =
        conn
        |> put_req_header("x-github-event", "workflow_job")
        |> put_req_header("x-github-delivery", delivery_guid)

      params = %{
        "action" => "queued",
        "installation" => %{"id" => installation_id},
        "workflow_job" => %{"id" => 76_773_615_870, "labels" => ["tuist-macos"]},
        "repository" => %{"full_name" => "tuist/tuist"}
      }

      result = GitHubController.handle(conn, params)

      assert result.status == 200

      assert_enqueued(
        worker: DispatchWorker,
        args: %{
          "payload" => params,
          "installation_id" => installation_id,
          "delivery_guid" => delivery_guid
        }
      )
    end

    test "enqueues for action=waiting", %{conn: conn} do
      installation_id = System.unique_integer([:positive])
      delivery_guid = "deadbeef-waiting"

      conn =
        conn
        |> put_req_header("x-github-event", "workflow_job")
        |> put_req_header("x-github-delivery", delivery_guid)

      params = %{
        "action" => "waiting",
        "installation" => %{"id" => installation_id},
        "workflow_job" => %{"id" => 76_773_615_871, "labels" => ["tuist-macos"]},
        "repository" => %{"full_name" => "tuist/tuist"}
      }

      result = GitHubController.handle(conn, params)

      assert result.status == 200

      assert_enqueued(
        worker: DispatchWorker,
        args: %{
          "payload" => params,
          "installation_id" => installation_id,
          "delivery_guid" => delivery_guid
        }
      )
    end

    test "200s without enqueueing when the payload has no installation.id", %{conn: conn} do
      conn =
        conn
        |> put_req_header("x-github-event", "workflow_job")
        |> put_req_header("x-github-delivery", "deadbeef-no-installation")

      params = %{
        "action" => "queued",
        "workflow_job" => %{"id" => 1, "labels" => ["tuist-macos"]},
        "repository" => %{"full_name" => "tuist/tuist"}
      }

      result = GitHubController.handle(conn, params)

      assert result.status == 200
      refute_enqueued(worker: DispatchWorker)
    end

    test "200s without enqueueing for action=in_progress (worker would treat it as ignored)",
         %{conn: conn} do
      conn =
        conn
        |> put_req_header("x-github-event", "workflow_job")
        |> put_req_header("x-github-delivery", "deadbeef-in-progress")

      params = %{
        "action" => "in_progress",
        "installation" => %{"id" => System.unique_integer([:positive])},
        "workflow_job" => %{"id" => 1, "labels" => ["tuist-macos"]},
        "repository" => %{"full_name" => "tuist/tuist"}
      }

      result = GitHubController.handle(conn, params)

      assert result.status == 200
      refute_enqueued(worker: DispatchWorker)
    end

    test "200s without enqueueing for unknown actions", %{conn: conn} do
      conn =
        conn
        |> put_req_header("x-github-event", "workflow_job")
        |> put_req_header("x-github-delivery", "deadbeef-unknown-action")

      params = %{
        "action" => "requested",
        "installation" => %{"id" => System.unique_integer([:positive])},
        "workflow_job" => %{"id" => 1, "labels" => ["tuist-macos"]},
        "repository" => %{"full_name" => "tuist/tuist"}
      }

      result = GitHubController.handle(conn, params)

      assert result.status == 200
      refute_enqueued(worker: DispatchWorker)
    end

    test "enqueues for action=completed", %{conn: conn} do
      installation_id = System.unique_integer([:positive])
      delivery_guid = "deadbeef-completed"

      conn =
        conn
        |> put_req_header("x-github-event", "workflow_job")
        |> put_req_header("x-github-delivery", delivery_guid)

      params = %{
        "action" => "completed",
        "installation" => %{"id" => installation_id},
        "workflow_job" => %{"id" => 2, "labels" => ["tuist-macos"]},
        "repository" => %{"full_name" => "tuist/tuist"}
      }

      result = GitHubController.handle(conn, params)

      assert result.status == 200

      assert_enqueued(
        worker: DispatchWorker,
        args: %{
          "payload" => params,
          "installation_id" => installation_id,
          "delivery_guid" => delivery_guid
        }
      )
    end
  end
end
