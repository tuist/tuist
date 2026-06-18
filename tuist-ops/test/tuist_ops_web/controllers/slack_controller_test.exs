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

  alias TuistOps.JIT.Approvals
  alias TuistOps.Previews
  alias TuistOps.JIT.Request
  alias TuistOps.JIT.SlackClient
  alias TuistOps.JIT.TailscaleClient
  alias TuistOps.Environment

  setup :verify_on_exit!

  setup do
    stub(Environment, :approvals_channel_id, fn -> "C_APPROVALS" end)
    stub(Environment, :previews_channel_id, fn -> "C_PREVIEWS" end)

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

    test "valid /elevate staging 5m \"reason\" → creates Request + ephemeral reply" do
      conn =
        TuistOpsWeb.SlackController.slash(
          build_conn(),
          %{"user_id" => "U_MAREK", "text" => "staging 5m fix flaky test"}
        )

      assert conn.status == 200
      assert {:ok, body} = JSON.decode(conn.resp_body)
      assert body["response_type"] == "ephemeral"
      assert body["text"] =~ "C_APPROVALS"

      assert Repo.one(from r in Request, where: r.status == "pending") |> Map.get(:intent) ==
               "fix flaky test"
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

    test "valid /preview create dispatches preview request" do
      expect(Previews, :request_create, fn attrs ->
        assert attrs.requester_email == "marek@tuist.dev"
        assert attrs.requester_slack_id == "U_MAREK"
        assert attrs.slack_channel_id == "C_PREVIEWS"
        assert attrs.slug == "demo"
        assert attrs.ttl_seconds == 7200
        assert attrs.ref_kind == "pr"
        assert attrs.ref_value == "123"
        assert attrs.reason == "test branch with Kura"
        {:ok, %TuistOps.Previews.Request{}}
      end)

      conn =
        TuistOpsWeb.SlackController.slash(
          build_conn(),
          %{
            "command" => "/preview",
            "user_id" => "U_MAREK",
            "text" => "create demo 2h pr:123 test branch with Kura"
          }
        )

      assert conn.status == 200
      {:ok, body} = JSON.decode(conn.resp_body)
      assert body["response_type"] == "ephemeral"
      assert body["text"] =~ "C_PREVIEWS"
    end

    test "valid /preview delete dispatches preview deletion" do
      expect(Previews, :request_delete, fn attrs ->
        assert attrs.requester_email == "marek@tuist.dev"
        assert attrs.requester_slack_id == "U_MAREK"
        assert attrs.slack_channel_id == "C_PREVIEWS"
        assert attrs.slug == "demo"
        assert attrs.reason == "done testing"
        {:ok, %TuistOps.Previews.Request{}}
      end)

      conn =
        TuistOpsWeb.SlackController.slash(
          build_conn(),
          %{"command" => "/preview", "user_id" => "U_MAREK", "text" => "delete demo done testing"}
        )

      assert conn.status == 200
      {:ok, body} = JSON.decode(conn.resp_body)
      assert body["response_type"] == "ephemeral"
      assert body["text"] =~ "C_PREVIEWS"
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
        assert msg =~ "second human"
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

    test "preview_delete action dispatches preview deletion and 200s" do
      expect(Previews, :request_delete, fn attrs ->
        assert attrs.requester_email == "pedro@tuist.dev"
        assert attrs.requester_slack_id == "U_PEDRO"
        assert attrs.slack_channel_id == "C_APPROVALS"
        assert attrs.slug == "demo"
        {:ok, %TuistOps.Previews.Request{}}
      end)

      conn =
        TuistOpsWeb.SlackController.interactive(build_conn(), %{
          "payload" =>
            JSON.encode!(%{
              "user" => %{"id" => "U_PEDRO"},
              "channel" => %{"id" => "C_APPROVALS"},
              "actions" => [%{"action_id" => "preview_delete", "value" => "demo"}]
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
