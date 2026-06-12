defmodule TuistOps.ProjectAccess.ApprovalsTest do
  use TuistOps.DataCase, async: true
  use Mimic

  alias TuistOps.JIT.SlackClient
  alias TuistOps.JIT.TailscaleClient
  alias TuistOps.ProjectAccess.Approvals
  alias TuistOps.ProjectAccess.Request
  alias TuistOps.Repo

  setup :verify_on_exit!

  describe "request_access/1 — read tier" do
    test "creates an approved request and an active grant immediately" do
      assert {:ok, :granted, grant} =
               Approvals.request_access(%{
                 tier: "read",
                 requester_email: "marek@tuist.dev",
                 account_handle: "acme",
                 reason: "investigate failing build",
                 return_to: "https://tuist.dev/acme/app",
                 ttl_seconds: 1800
               })

      assert grant.tier == "read"
      assert grant.status == "active"
      assert grant.account_handle == "acme"
      assert grant.requester_email == "marek@tuist.dev"

      request = Repo.get(Request, grant.request_id)
      assert request.status == "approved"
      assert request.tier == "read"
    end

    test "clamps the TTL to the read maximum" do
      {:ok, :granted, grant} =
        Approvals.request_access(%{
          tier: "read",
          requester_email: "marek@tuist.dev",
          account_handle: "acme",
          reason: "investigate failing build",
          return_to: "https://tuist.dev/acme/app",
          ttl_seconds: 99_999
        })

      assert DateTime.diff(grant.expires_at, DateTime.utc_now()) <=
               Approvals.read_max_ttl_seconds() + 5
    end
  end

  describe "request_access/1 — admin tier" do
    test "creates a pending request, posts a Slack card, no grant yet" do
      stub(SlackClient, :post_message, fn _channel, _blocks, _opts -> {:ok, "1780000000.0001"} end)

      assert {:ok, :pending, request} =
               Approvals.request_access(%{
                 tier: "admin",
                 requester_email: "marek@tuist.dev",
                 account_handle: "acme",
                 reason: "rotate leaked credentials",
                 return_to: "https://tuist.dev/acme/app",
                 ttl_seconds: 1800,
                 slack_channel_id: "C_TEST"
               })

      assert request.status == "pending"
      assert request.tier == "admin"
      assert request.slack_message_ts == "1780000000.0001"
      assert Approvals.active_grant_for_request(request.id) == nil
    end
  end

  describe "approve/2" do
    setup do
      stub(SlackClient, :post_message, fn _channel, _blocks, _opts -> {:ok, "ts1"} end)
      stub(SlackClient, :update_message, fn _channel, _ts, _blocks, _opts -> :ok end)

      {:ok, :pending, request} =
        Approvals.request_access(%{
          tier: "admin",
          requester_email: "marek@tuist.dev",
          account_handle: "acme",
          reason: "rotate leaked credentials",
          return_to: "https://tuist.dev/acme/app",
          ttl_seconds: 1800,
          slack_channel_id: "C_TEST"
        })

      %{request: request}
    end

    test "a second Owner/Admin approves and spawns an admin grant", %{request: request} do
      stub(TailscaleClient, :user_role, fn "pedro@tuist.dev" -> {:ok, :owner} end)

      assert {:ok, approved, grant} =
               Approvals.approve(request.id, %{slack_id: "U_PEDRO", email: "pedro@tuist.dev"})

      assert approved.status == "approved"
      assert approved.approver_email == "pedro@tuist.dev"
      assert grant.tier == "admin"
      assert grant.status == "active"
      assert grant.account_handle == "acme"
    end

    test "the requester cannot self-approve", %{request: request} do
      assert {:error, :cannot_self_approve} =
               Approvals.approve(request.id, %{slack_id: "U_MAREK", email: "marek@tuist.dev"})
    end

    test "self-approval is rejected case-insensitively", %{request: request} do
      assert {:error, :cannot_self_approve} =
               Approvals.approve(request.id, %{slack_id: "U_MAREK", email: "Marek@TUIST.dev"})
    end

    test "a Member cannot approve admin access", %{request: request} do
      stub(TailscaleClient, :user_role, fn _ -> {:ok, :member} end)

      assert {:error, :approver_not_authorized} =
               Approvals.approve(request.id, %{slack_id: "U_ENG", email: "eng@tuist.dev"})
    end

    test "is idempotent on replay of an already-approved request", %{request: request} do
      stub(TailscaleClient, :user_role, fn _ -> {:ok, :owner} end)

      {:ok, _req, grant} =
        Approvals.approve(request.id, %{slack_id: "U_P", email: "pedro@tuist.dev"})

      assert {:ok, _req2, grant2} =
               Approvals.approve(request.id, %{slack_id: "U_P", email: "pedro@tuist.dev"})

      assert grant2.id == grant.id
    end
  end

  describe "approve/2 and deny/2 — direct rows" do
    test "rejects an approval whose window has passed" do
      stub(SlackClient, :update_message, fn _channel, _ts, _blocks, _opts -> :ok end)

      request = insert_admin_request!(%{expires_at: past(60)})

      assert {:error, :approval_expired} =
               Approvals.approve(request.id, %{slack_id: "U_P", email: "pedro@tuist.dev"})

      assert Repo.get(Request, request.id).status == "expired"
    end

    test "deny marks the request denied" do
      stub(SlackClient, :update_message, fn _channel, _ts, _blocks, _opts -> :ok end)

      request = insert_admin_request!(%{})

      assert {:ok, denied} =
               Approvals.deny(request.id, %{slack_id: "U_P", email: "pedro@tuist.dev"})

      assert denied.status == "denied"
      assert denied.approver_email == "pedro@tuist.dev"
    end
  end

  defp insert_admin_request!(overrides) do
    %{
      requester_email: "marek@tuist.dev",
      account_handle: "acme",
      tier: "admin",
      reason: "rotate leaked credentials",
      return_to: "https://tuist.dev/acme/app",
      ttl_seconds: 1800,
      slack_channel_id: "C_TEST",
      status: "pending",
      expires_at: DateTime.add(now(), 600, :second)
    }
    |> Map.merge(overrides)
    |> Request.create_changeset()
    |> Repo.insert!()
    |> Request.transition_changeset(%{slack_message_ts: "ts0"})
    |> Repo.update!()
  end

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)
  defp past(seconds), do: DateTime.add(now(), -seconds, :second)
end
