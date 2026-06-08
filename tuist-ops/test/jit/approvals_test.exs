defmodule TuistOps.JIT.ApprovalsTest do
  use TuistOps.DataCase, async: true
  use Mimic

  alias TuistOps.Repo
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

  describe "approve/2 — approver trust tier (second-human path)" do
    test "rejects a Member approving another engineer's production request" do
      stub_default_roles()
      stub(SlackClient, :update_message, fn _, _, _ -> :ok end)

      req =
        insert_request!(%{
          requester_email: "marek@tuist.dev",
          requester_slack_id: "U_MAREK",
          target_group: "group:tuist-prod-write"
        })

      assert {:error, :approver_not_authorized} =
               Approvals.approve(req.id, %{
                 slack_id: "U_EDUARDO",
                 email: "eduardo.ext@tuist.dev"
               })

      # No Elevation row created when the approver gate trips.
      assert Repo.get_by(Elevation, request_id: req.id) == nil
      # And the Request stays pending so an Owner/Admin can still
      # come along and approve.
      assert %Request{status: "pending"} = Repo.get!(Request, req.id)
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

end
