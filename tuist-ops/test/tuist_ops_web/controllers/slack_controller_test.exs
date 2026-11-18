defmodule TuistOpsWeb.SlackControllerTest do
  @moduledoc """
  Two Slack-webhook endpoints behind `SlackWebhookPlug`:

    POST /webhooks/slack/slash       — `/elevate <env> [ttl] <intent>`
    POST /webhooks/slack/interactive — Block Kit button callbacks

  These tests exercise the controller in isolation (DataCase
  sandbox + Mimic on side-effecting collaborators) and skip the
  signature-verifying plug — that plug has its own dedicated test
  in plugs/slack_webhook_plug_test.exs.
  """

  use TuistOps.DataCase, async: true
  use Mimic

  alias TuistOps.GitHub.OrgMembership
  alias TuistOps.JIT.Approvals
  alias TuistOps.JIT.Request
  alias TuistOps.JIT.SlackClient
  alias TuistOps.JIT.TailscaleClient
  alias TuistOps.Environment

  setup :verify_on_exit!

  setup do
    stub(Environment, :approvals_channel_id, fn -> "C_APPROVALS" end)

    # Slack-user → email lookup is needed by every controller path.
    # Map known fixtures by slack id; unknown ids resolve to the
    # slack id @example so tests fail-loud rather than silently
    # passing on a nil email.
    stub(SlackClient, :user_email, fn
      "U_MAREK" -> {:ok, "marek@tuist.dev"}
      "U_PEDRO" -> {:ok, "pedro@tuist.dev"}
      "U_ENG" -> {:ok, "eduardo@tuist.dev"}
      "U_TEST" -> {:ok, "marek@tuist.dev"}
      id -> {:ok, "#{id}@example.com"}
    end)

    :ok
  end

  # Slack signature is enforced upstream by SlackWebhookPlug,
  # which has its own dedicated test. Here we drive the controller
  # actions directly through a synthetic %Plug.Conn{} so these
  # tests focus purely on the controller's dispatch + error
  # surfacing.
  defp build_conn do
    Phoenix.ConnTest.build_conn()
    |> Plug.Conn.put_req_header("content-type", "application/x-www-form-urlencoded")
  end

  defp insert_pending_request!(overrides \\ %{}) do
    base = %{
      requester_email: "marek@tuist.dev",
      requester_slack_id: "U_MAREK",
      target_group: "group:tuist-staging-write",
      intent: "test request",
      ttl_seconds: 600,
      slack_channel_id: "C_APPROVALS",
      expires_at: DateTime.add(DateTime.utc_now(), 600, :second),
      status: "pending"
    }

    base
    |> Map.merge(overrides)
    |> Request.create_changeset()
    |> Repo.insert!()
  end

  describe "POST /webhooks/slack/slash" do
    setup do
      stub(SlackClient, :post_message, fn _channel, _blocks ->
        {:ok, "1700000000.000001"}
      end)

      stub(TailscaleClient, :user_role, fn _ -> {:ok, :owner} end)

      :ok
    end

    test "valid /elevate canary 5m \"reason\" → creates Request + ephemeral reply" do
      conn =
        TuistOpsWeb.SlackController.slash(
          build_conn(),
          %{"user_id" => "U_MAREK", "text" => "canary 5m fix flaky test"}
        )

      assert conn.status == 200
      assert {:ok, body} = JSON.decode(conn.resp_body)
      assert body["response_type"] == "ephemeral"
      assert body["text"] =~ "C_APPROVALS"

      assert Repo.one(from r in Request, where: r.status == "pending") |> Map.get(:intent) ==
               "fix flaky test"
    end

    test "/elevate --thread → points to Atlas, no Request" do
      for text <- [
            "prod --thread T-01a1a59e-55fb-744b-9415-b85a337f24d2 30m restart wedged kura pod",
            "canary --thread",
            # A misplaced or smart-dashed flag must not become a personal elevation.
            "prod 30m --thread T-01a1a59e-55fb-744b-9415-b85a337f24d2 restart pod",
            "prod —thread T-01a1a59e-55fb-744b-9415-b85a337f24d2 restart pod",
            "prod --Thread T-01a1a59e-55fb-744b-9415-b85a337f24d2 restart pod"
          ] do
        conn =
          TuistOpsWeb.SlackController.slash(build_conn(), %{
            "user_id" => "U_MAREK",
            "text" => text
          })

        assert {:ok, %{"response_type" => "ephemeral", "text" => reply}} =
                 JSON.decode(conn.resp_body)

        assert reply =~ "request_cluster_elevation"
      end

      assert Repo.aggregate(Request, :count) == 0
    end

    test "/elevate staging → rejected as already writable, no Request created" do
      conn =
        TuistOpsWeb.SlackController.slash(
          build_conn(),
          %{"user_id" => "U_MAREK", "text" => "staging 5m fix flaky test"}
        )

      assert conn.status == 200
      {:ok, body} = JSON.decode(conn.resp_body)
      assert body["response_type"] == "ephemeral"
      assert body["text"] =~ "no elevation needed"
      assert Repo.aggregate(Request, :count) == 0
    end

    test "usage + unknown-env messages don't offer staging" do
      usage =
        build_conn()
        |> TuistOpsWeb.SlackController.slash(%{"user_id" => "U_MAREK"})
        |> then(&JSON.decode!(&1.resp_body))
        |> Map.fetch!("text")

      bad_env =
        build_conn()
        |> TuistOpsWeb.SlackController.slash(%{
          "user_id" => "U_MAREK",
          "text" => "europe 5m nope"
        })
        |> then(&JSON.decode!(&1.resp_body))
        |> Map.fetch!("text")

      for text <- [usage, bad_env] do
        assert text =~ "canary"
        assert text =~ "production"
        refute text =~ "staging"
      end
    end

    test "/elevate-github <login> [duration] <intent> → GitHub admin Request" do
      stub(OrgMembership, :membership, fn "esnunes" ->
        {:ok, %{state: "active", role: "member"}}
      end)

      conn =
        TuistOpsWeb.SlackController.slash(
          build_conn(),
          %{
            "command" => "/elevate-github",
            "user_id" => "U_MAREK",
            "text" => "esnunes 30m fix branch protection"
          }
        )

      assert {:ok, %{"response_type" => "ephemeral"}} = JSON.decode(conn.resp_body)

      assert %Request{
               target_group: "github:org-admin",
               github_login: "esnunes",
               ttl_seconds: 1800,
               intent: "fix branch protection"
             } = Repo.one!(Request)
    end

    test "/elevate-github without a duration uses the default TTL" do
      stub(OrgMembership, :membership, fn _ -> {:ok, %{state: "active", role: "member"}} end)

      TuistOpsWeb.SlackController.slash(
        build_conn(),
        %{
          "command" => "/elevate-github",
          "user_id" => "U_MAREK",
          "text" => "esnunes fix branch protection"
        }
      )

      assert %Request{ttl_seconds: ttl, intent: "fix branch protection"} = Repo.one!(Request)
      assert ttl == Approvals.default_ttl_seconds()
    end

    test "/elevate-github with a missing login, intent, or invalid login → ephemeral error, no Request" do
      reject(&OrgMembership.membership/1)

      for text <- ["", "-bad- fix branch protection", "esnunes"] do
        conn =
          TuistOpsWeb.SlackController.slash(build_conn(), %{
            "command" => "/elevate-github",
            "user_id" => "U_MAREK",
            "text" => text
          })

        assert {:ok, %{"response_type" => "ephemeral", "text" => message}} =
                 JSON.decode(conn.resp_body)

        refute message =~ "Internal error"
      end

      assert Repo.aggregate(Request, :count) == 0
    end

    test "/elevate-github for an existing admin explains there is nothing to elevate" do
      stub(OrgMembership, :membership, fn _ -> {:ok, %{state: "active", role: "admin"}} end)

      conn =
        TuistOpsWeb.SlackController.slash(
          build_conn(),
          %{
            "command" => "/elevate-github",
            "user_id" => "U_MAREK",
            "text" => "esnunes fix branch protection"
          }
        )

      assert JSON.decode!(conn.resp_body)["text"] =~ "already a GitHub organization admin"
    end

    test "/elevate no longer treats github as an env" do
      reject(&OrgMembership.membership/1)

      conn =
        TuistOpsWeb.SlackController.slash(build_conn(), %{
          "command" => "/elevate",
          "user_id" => "U_MAREK",
          "text" => "github esnunes fix branch protection"
        })

      assert JSON.decode!(conn.resp_body)["text"] =~ "`/elevate-github <login>"
      assert Repo.aggregate(Request, :count) == 0
    end

    test "/elevate-github explains a GitHub API failure instead of an internal error" do
      stub(OrgMembership, :membership, fn _ ->
        {:error, {:github_status, 403, %{"message" => "Resource not accessible by integration"}}}
      end)

      conn =
        TuistOpsWeb.SlackController.slash(build_conn(), %{
          "command" => "/elevate-github",
          "user_id" => "U_MAREK",
          "text" => "esnunes fix branch protection"
        })

      text = JSON.decode!(conn.resp_body)["text"]
      assert text =~ "GitHub returned 403 (Resource not accessible by integration)"
      assert text =~ "Members permission"
      refute text =~ "Internal error"
    end

    test "/elevate without args → usage message" do
      conn = TuistOpsWeb.SlackController.slash(build_conn(), %{"user_id" => "U_MAREK"})
      assert conn.status == 200
      {:ok, body} = JSON.decode(conn.resp_body)
      assert body["response_type"] == "ephemeral"
      assert body["text"] =~ "elevate"
    end

    test "/elevate with bad env → ephemeral error" do
      conn =
        TuistOpsWeb.SlackController.slash(
          build_conn(),
          %{"user_id" => "U_MAREK", "text" => "europe 5m nope"}
        )

      assert conn.status == 200
      {:ok, body} = JSON.decode(conn.resp_body)
      assert body["response_type"] == "ephemeral"
    end
  end

  describe "POST /webhooks/slack/interactive" do
    setup do
      stub(SlackClient, :post_message, fn _, _ -> {:ok, "ts.1"} end)
      stub(SlackClient, :update_message, fn _, _, _ -> :ok end)
      stub(SlackClient, :ephemeral, fn _, _, _ -> :ok end)
      stub(TailscaleClient, :user_role, fn _ -> {:ok, :owner} end)
      :ok
    end

    test "approve action dispatches to Approvals.approve and 200s" do
      request = insert_pending_request!()

      expect(Approvals, :approve, fn id, %{slack_id: _, email: _} ->
        assert id == request.id
        {:ok, request, %TuistOps.JIT.Elevation{}}
      end)

      conn =
        TuistOpsWeb.SlackController.interactive(build_conn(), %{
          "payload" =>
            JSON.encode!(%{
              "user" => %{"id" => "U_PEDRO"},
              "channel" => %{"id" => "C_APPROVALS"},
              "actions" => [
                %{
                  "action_id" => "approve",
                  "value" => "#{request.id}:U_MAREK"
                }
              ]
            })
        })

      assert conn.status == 200
    end

    test "self-approval rejection surfaces ephemeral hint, still 200" do
      request = insert_pending_request!()

      stub(Approvals, :approve, fn _, _ -> {:error, :cannot_self_approve} end)

      expect(SlackClient, :ephemeral, fn _channel, _user, msg ->
        assert msg =~ "self-approve"
        :ok
      end)

      conn =
        TuistOpsWeb.SlackController.interactive(build_conn(), %{
          "payload" =>
            JSON.encode!(%{
              "user" => %{"id" => "U_MAREK"},
              "channel" => %{"id" => "C_APPROVALS"},
              "actions" => [%{"action_id" => "approve", "value" => "#{request.id}:U_MAREK"}]
            })
        })

      assert conn.status == 200
    end

    test "approver-not-authorized surfaces ephemeral hint, still 200" do
      request = insert_pending_request!(%{target_group: "group:tuist-production-write"})

      stub(Approvals, :approve, fn _, _ -> {:error, :approver_not_authorized} end)

      expect(SlackClient, :ephemeral, fn _, _, msg ->
        assert msg =~ "Tailscale role"
        :ok
      end)

      conn =
        TuistOpsWeb.SlackController.interactive(build_conn(), %{
          "payload" =>
            JSON.encode!(%{
              "user" => %{"id" => "U_ENG"},
              "channel" => %{"id" => "C_APPROVALS"},
              "actions" => [%{"action_id" => "approve", "value" => "#{request.id}:U_MAREK"}]
            })
        })

      assert conn.status == 200
    end

    test "a failed GitHub promotion tells the approver why" do
      request =
        insert_pending_request!(%{target_group: "github:org-admin", github_login: "esnunes"})

      stub(OrgMembership, :membership, fn _ -> {:ok, %{state: "active", role: "member"}} end)

      stub(OrgMembership, :set_role, fn _, _ ->
        {:error, {:github_status, 403, %{"message" => "Resource not accessible by integration"}}}
      end)

      expect(SlackClient, :ephemeral, fn "C_APPROVALS", "U_PEDRO", msg ->
        assert msg =~ "Promoting the GitHub account failed: GitHub returned 403"
        :ok
      end)

      conn =
        TuistOpsWeb.SlackController.interactive(build_conn(), %{
          "payload" =>
            JSON.encode!(%{
              "user" => %{"id" => "U_PEDRO"},
              "channel" => %{"id" => "C_APPROVALS"},
              "actions" => [%{"action_id" => "approve", "value" => "#{request.id}:U_MAREK"}]
            })
        })

      assert conn.status == 200
      assert Repo.get!(Request, request.id).status == "failed"
    end

    test "deny action dispatches to Approvals.deny and 200s" do
      request = insert_pending_request!()

      expect(Approvals, :deny, fn id, _actor ->
        assert id == request.id
        {:ok, request}
      end)

      conn =
        TuistOpsWeb.SlackController.interactive(build_conn(), %{
          "payload" =>
            JSON.encode!(%{
              "user" => %{"id" => "U_PEDRO"},
              "channel" => %{"id" => "C_APPROVALS"},
              "actions" => [%{"action_id" => "deny", "value" => "#{request.id}:U_MAREK"}]
            })
        })

      assert conn.status == 200
    end

    test "unknown action_id swallowed with 200 (so Slack doesn't retry)" do
      conn =
        TuistOpsWeb.SlackController.interactive(build_conn(), %{
          "payload" =>
            JSON.encode!(%{
              "user" => %{"id" => "U_X"},
              "channel" => %{"id" => "C_APPROVALS"},
              "actions" => [%{"action_id" => "unknown", "value" => "x"}]
            })
        })

      assert conn.status == 200
    end

    test "missing payload field → 400" do
      conn = TuistOpsWeb.SlackController.interactive(build_conn(), %{})
      assert conn.status == 400
    end

    test "invalid JSON payload → 400" do
      conn =
        TuistOpsWeb.SlackController.interactive(build_conn(), %{"payload" => "{not json"})

      assert conn.status == 400
    end
  end
end
