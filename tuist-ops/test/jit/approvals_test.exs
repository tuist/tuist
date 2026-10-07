defmodule TuistOps.JIT.ApprovalsTest do
  use TuistOps.DataCase, async: true
  use Mimic

  alias TuistOps.Repo
  alias TuistOps.GitHub.OrgMembership
  alias TuistOps.JIT.Approvals
  alias TuistOps.JIT.Elevation
  alias TuistOps.JIT.Request
  alias TuistOps.JIT.SlackClient
  alias TuistOps.JIT.TailscaleClient

  setup :verify_on_exit!

  # Default role map for tests that don't care about role specifics.
  # Tests that DO care override the stub locally.
  defp stub_default_roles do
    roles = %{
      "marek@tuist.dev" => :owner,
      "pedro@tuist.dev" => :admin,
      "eduardo.ext@tuist.dev" => :member
    }

    stub(TailscaleClient, :user_role, fn email ->
      case Map.fetch(roles, email) do
        {:ok, role} -> {:ok, role}
        :error -> {:error, :not_found}
      end
    end)
  end

  # Minimal Request row directly via Repo.insert! to keep these
  # tests free of any factory dependency.
  defp insert_request!(overrides) do
    base = %{
      requester_email: "marek@tuist.dev",
      requester_slack_id: "U_MAREK",
      target_group: "group:tuist-staging-write",
      intent: "approvals test request",
      ttl_seconds: 900,
      slack_channel_id: "C_TEST",
      expires_at: DateTime.add(DateTime.utc_now(), 600, :second)
    }

    base
    |> Map.merge(overrides)
    |> Request.create_changeset()
    # slack_message_ts isn't accepted by create_changeset (it's set
    # by request_elevation after the Slack post), so add it via a
    # follow-up transition changeset that the test setup uses.
    |> Repo.insert!()
    |> Request.transition_changeset(%{slack_message_ts: "1780000000.000000"})
    |> Repo.update!()
  end

  describe "approve/2 — expired approval window" do
    test "rejects an approval whose request.expires_at is in the past" do
      stub(SlackClient, :update_message, fn _channel, _ts, _blocks -> :ok end)

      req = insert_request!(%{expires_at: DateTime.add(DateTime.utc_now(), -3600, :second)})

      assert {:error, :approval_expired} =
               Approvals.approve(req.id, %{slack_id: "U_OTHER", email: "pedro@tuist.dev"})
    end

    test "transitions the request to :expired so the row reflects reality" do
      stub(SlackClient, :update_message, fn _channel, _ts, _blocks -> :ok end)

      req = insert_request!(%{expires_at: DateTime.add(DateTime.utc_now(), -3600, :second)})

      _ = Approvals.approve(req.id, %{slack_id: "U_OTHER", email: "pedro@tuist.dev"})

      assert %Request{status: "expired"} = Repo.get!(Request, req.id)
    end

    test "updates the original Slack card to the 'expired' terminal state" do
      pid = self()

      stub(SlackClient, :update_message, fn channel, ts, blocks ->
        send(pid, {:slack_update, channel, ts, blocks})
        :ok
      end)

      req = insert_request!(%{expires_at: DateTime.add(DateTime.utc_now(), -3600, :second)})

      _ = Approvals.approve(req.id, %{slack_id: "U_OTHER", email: "pedro@tuist.dev"})

      assert_received {:slack_update, "C_TEST", "1780000000.000000", blocks}
      # SlackBlocks.closed renders a single section block whose text
      # includes the status label.
      assert blocks |> List.first() |> get_in([:text, :text]) =~ "expired"
    end

    test "does NOT create an Elevation row when expired" do
      stub(SlackClient, :update_message, fn _, _, _ -> :ok end)

      req = insert_request!(%{expires_at: DateTime.add(DateTime.utc_now(), -3600, :second)})

      assert {:error, :approval_expired} =
               Approvals.approve(req.id, %{slack_id: "U_OTHER", email: "pedro@tuist.dev"})

      # No Elevation row created when the expiry gate trips.
      assert Repo.get_by(Elevation, request_id: req.id) == nil
    end
  end

  describe "approve/2 — self-approval" do
    test "Owner self-approves their own production request -> elevation created" do
      stub_default_roles()
      stub(SlackClient, :update_message, fn _, _, _ -> :ok end)

      req =
        insert_request!(%{
          requester_email: "marek@tuist.dev",
          requester_slack_id: "U_MAREK",
          target_group: "group:tuist-production-write"
        })

      assert {:ok, %Request{status: "approved"}, %Elevation{status: "active"}} =
               Approvals.approve(req.id, %{slack_id: "U_MAREK", email: "marek@tuist.dev"})

      assert Repo.get_by(Elevation, request_id: req.id)
    end

    test "Member self-approves their own production request -> elevation created" do
      # The behaviour this change restores: a Member self-services a
      # production elevation without needing a second human.
      stub_default_roles()
      stub(SlackClient, :update_message, fn _, _, _ -> :ok end)

      req =
        insert_request!(%{
          requester_email: "eduardo.ext@tuist.dev",
          requester_slack_id: "U_EDUARDO",
          target_group: "group:tuist-production-write"
        })

      assert {:ok, %Request{status: "approved"}, %Elevation{status: "active"}} =
               Approvals.approve(req.id, %{
                 slack_id: "U_EDUARDO",
                 email: "eduardo.ext@tuist.dev"
               })

      assert Repo.get_by(Elevation, request_id: req.id)
    end

    test "requester whose role can't self-approve is rejected (:cannot_self_approve)" do
      # A non-engineering requester (Auditor) clicking Approve on
      # their own request hits the self-approve gate: no elevation,
      # request stays pending for an engineering-role approver.
      stub(TailscaleClient, :user_role, fn
        "auditor@tuist.dev" -> {:ok, :auditor}
        _ -> {:error, :not_found}
      end)

      stub(SlackClient, :update_message, fn _, _, _ -> :ok end)

      req =
        insert_request!(%{
          requester_email: "auditor@tuist.dev",
          requester_slack_id: "U_AUDITOR",
          target_group: "group:tuist-staging-write"
        })

      assert {:error, :cannot_self_approve} =
               Approvals.approve(req.id, %{slack_id: "U_AUDITOR", email: "auditor@tuist.dev"})

      assert Repo.get_by(Elevation, request_id: req.id) == nil
      assert %Request{status: "pending"} = Repo.get!(Request, req.id)
    end
  end

  describe "approve/2 — approver trust tier (second-human path)" do
    test "allows a Member to approve another engineer's production request" do
      stub_default_roles()
      stub(SlackClient, :update_message, fn _, _, _ -> :ok end)

      req =
        insert_request!(%{
          requester_email: "marek@tuist.dev",
          requester_slack_id: "U_MAREK",
          target_group: "group:tuist-production-write"
        })

      assert {:ok, %Request{status: "approved"}, %Elevation{status: "active"}} =
               Approvals.approve(req.id, %{
                 slack_id: "U_EDUARDO",
                 email: "eduardo.ext@tuist.dev"
               })

      assert Repo.get_by(Elevation, request_id: req.id)
    end

    test "rejects an off-tailnet approver for any env" do
      stub(TailscaleClient, :user_role, fn _ -> {:error, :not_found} end)
      stub(SlackClient, :update_message, fn _, _, _ -> :ok end)

      req =
        insert_request!(%{
          requester_email: "marek@tuist.dev",
          requester_slack_id: "U_MAREK",
          target_group: "group:tuist-staging-write"
        })

      assert {:error, :approver_not_authorized} =
               Approvals.approve(req.id, %{
                 slack_id: "U_GHOST",
                 email: "ghost@evil.example"
               })
    end

    test "rejects admin-flavor non-engineering roles (Auditor, Billing admin)" do
      stub(TailscaleClient, :user_role, fn
        "marek@tuist.dev" -> {:ok, :owner}
        "auditor@tuist.dev" -> {:ok, :auditor}
        _ -> {:error, :not_found}
      end)

      stub(SlackClient, :update_message, fn _, _, _ -> :ok end)

      req =
        insert_request!(%{
          requester_email: "marek@tuist.dev",
          requester_slack_id: "U_MAREK",
          target_group: "group:tuist-staging-write"
        })

      assert {:error, :approver_not_authorized} =
               Approvals.approve(req.id, %{
                 slack_id: "U_AUDITOR",
                 email: "auditor@tuist.dev"
               })
    end
  end

  describe "GitHub admin elevation" do
    @github "github:org-admin"

    defp github_request_attrs(overrides \\ %{}) do
      Map.merge(
        %{
          requester_email: "eduardo.ext@tuist.dev",
          requester_slack_id: "U_EDUARDO",
          target_group: @github,
          github_login: "EsNunes",
          intent: "fix branch protection",
          ttl_seconds: 900,
          slack_channel_id: "C_TEST"
        },
        overrides
      )
    end

    test "request_elevation/1 posts the card for an active member and downcases the login" do
      stub_default_roles()

      stub(OrgMembership, :membership, fn "esnunes" ->
        {:ok, %{state: "active", role: "member"}}
      end)

      stub(SlackClient, :post_message, fn _channel, _blocks -> {:ok, "1780000000.000001"} end)

      assert {:ok, %Request{github_login: "esnunes", status: "pending"}} =
               Approvals.request_elevation(github_request_attrs())
    end

    test "request_elevation/1 rejects a login that is already an admin" do
      stub(OrgMembership, :membership, fn _ -> {:ok, %{state: "active", role: "admin"}} end)
      reject(&SlackClient.post_message/2)

      assert {:error, {:github_already_admin, "esnunes"}} =
               Approvals.request_elevation(github_request_attrs())

      assert Repo.aggregate(Request, :count) == 0
    end

    test "request_elevation/1 rejects a non-member or pending member" do
      reject(&SlackClient.post_message/2)

      stub(OrgMembership, :membership, fn _ -> {:error, :not_member} end)

      assert {:error, {:github_not_member, "esnunes"}} =
               Approvals.request_elevation(github_request_attrs())

      stub(OrgMembership, :membership, fn _ -> {:ok, %{state: "pending", role: "member"}} end)

      assert {:error, {:github_not_member, "esnunes"}} =
               Approvals.request_elevation(github_request_attrs())
    end

    test "request_elevation/1 rejects an invalid login before calling GitHub" do
      reject(&OrgMembership.membership/1)

      assert {:error, %Ecto.Changeset{}} =
               Approvals.request_elevation(github_request_attrs(%{github_login: "-bad-"}))
    end

    test "approve/2 promotes the login and records it on the elevation" do
      stub_default_roles()
      stub(SlackClient, :update_message, fn _, _, _ -> :ok end)

      stub(OrgMembership, :membership, fn "esnunes" ->
        {:ok, %{state: "active", role: "member"}}
      end)

      expect(OrgMembership, :set_role, fn "esnunes", "admin" ->
        {:ok, %{state: "active", role: "admin"}}
      end)

      req = insert_request!(github_request_attrs())

      assert {:ok, %Request{status: "approved"}, %Elevation{github_login: "esnunes"}} =
               Approvals.approve(req.id, %{slack_id: "U_EDUARDO", email: "eduardo.ext@tuist.dev"})
    end

    test "approve/2 marks the request failed without an elevation when GitHub fails" do
      stub_default_roles()
      stub(OrgMembership, :membership, fn _ -> {:ok, %{state: "active", role: "member"}} end)
      stub(OrgMembership, :set_role, fn _, _ -> {:error, {:github_status, 403, %{}}} end)
      pid = self()

      stub(SlackClient, :update_message, fn _, _, blocks ->
        send(pid, {:slack_update, blocks})
        :ok
      end)

      req = insert_request!(github_request_attrs())

      assert {:error, {:github_promote_failed, {:github_status, 403, _}}} =
               Approvals.approve(req.id, %{slack_id: "U_EDUARDO", email: "eduardo.ext@tuist.dev"})

      assert %Request{status: "failed"} = Repo.get!(Request, req.id)
      refute Repo.get_by(Elevation, request_id: req.id)
      assert_received {:slack_update, [%{text: %{text: text}}]}
      assert text =~ "GitHub admin elevation: failed"
    end

    test "revoke/2 pulls the GitHub revert forward" do
      stub_default_roles()
      stub(SlackClient, :update_message, fn _, _, _ -> :ok end)
      stub(OrgMembership, :membership, fn _ -> {:ok, %{state: "active", role: "member"}} end)
      stub(OrgMembership, :set_role, fn _, _ -> {:ok, %{state: "active", role: "admin"}} end)

      req = insert_request!(github_request_attrs())

      {:ok, _req, elev} =
        Approvals.approve(req.id, %{slack_id: "U_EDUARDO", email: "eduardo.ext@tuist.dev"})

      assert {:ok, _} = Approvals.revoke(elev.id, %{slack_id: "U_EDUARDO"})

      assert [%Oban.Job{scheduled_at: scheduled_at}] =
               Repo.all(
                 from j in Oban.Job, where: j.worker == "TuistOps.JIT.Workers.RevertWorker"
               )

      assert DateTime.diff(scheduled_at, DateTime.utc_now()) <= 1
    end

    test "request_elevation/1 reports a GitHub API failure without blaming the login" do
      stub(OrgMembership, :membership, fn _ -> {:error, {:github_status, 403, %{}}} end)

      assert {:error, {:github_api_failed, {:github_status, 403, _}}} =
               Approvals.request_elevation(github_request_attrs())
    end

    test "approve/2 refuses to promote a login that became admin meanwhile" do
      stub_default_roles()
      stub(SlackClient, :update_message, fn _, _, _ -> :ok end)
      stub(OrgMembership, :membership, fn _ -> {:ok, %{state: "active", role: "admin"}} end)
      reject(&OrgMembership.set_role/2)

      req = insert_request!(github_request_attrs())

      assert {:error, {:github_promote_failed, :github_already_admin}} =
               Approvals.approve(req.id, %{slack_id: "U_EDUARDO", email: "eduardo.ext@tuist.dev"})
    end
  end
end
