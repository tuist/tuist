defmodule Tuist.TailscaleJIT.SlackBlocksTest do
  use ExUnit.Case, async: true

  alias Tuist.TailscaleJIT.Elevation
  alias Tuist.TailscaleJIT.Request
  alias Tuist.TailscaleJIT.SlackBlocks

  describe "encode_value/1 + decode_value/1" do
    test "round-trips request id + requester slack id" do
      req = %Request{id: 42, requester_slack_id: "U123"}
      assert SlackBlocks.encode_value(req) == "42:U123"
      assert SlackBlocks.decode_value("42:U123") == {:ok, 42, "U123"}
    end

    test "decode rejects malformed values" do
      assert SlackBlocks.decode_value("not-an-id:U123") == :error
      assert SlackBlocks.decode_value("noseparator") == :error
    end
  end

  describe "pending/1" do
    test "carries the requester slack id in the Approve button value" do
      req = sample_request()
      [_, _, %{elements: elements}] = SlackBlocks.pending(req)
      approve = Enum.find(elements, &(&1.action_id == "approve"))
      assert approve.value == "#{req.id}:#{req.requester_slack_id}"
    end

    test "includes a Deny button alongside Approve" do
      [_, _, %{elements: elements}] = SlackBlocks.pending(sample_request())
      assert Enum.any?(elements, &(&1.action_id == "approve"))
      assert Enum.any?(elements, &(&1.action_id == "deny"))
    end

    test "shows the 'cannot self-approve' hint by default" do
      [_, %{elements: [%{text: hint}]}, _] = SlackBlocks.pending(sample_request())
      assert hint =~ "cannot approve their own request"
    end

    test "suppresses the 'cannot self-approve' hint when policy allows it" do
      [_, %{elements: [%{text: hint}]}, _] =
        SlackBlocks.pending(sample_request(), self_approval_allowed?: true)

      refute hint =~ "cannot approve their own request"
    end
  end

  describe "active/2" do
    test "renders a Revoke button carrying the elevation id" do
      req = sample_request()
      elev = %Elevation{id: 7, expires_at: DateTime.add(DateTime.utc_now(), 900, :second)}
      [_, _, %{elements: [revoke]}] = SlackBlocks.active(req, elev)
      assert revoke.action_id == "revoke"
      assert revoke.value == "7"
    end
  end

  describe "closed/3" do
    test "renders only a section block (no actions, terminal state)" do
      blocks = SlackBlocks.closed(sample_request(), "denied")
      assert length(blocks) == 1
      [block] = blocks
      assert block.type == "section"
    end
  end

  defp sample_request do
    %Request{
      id: 1,
      requester_slack_id: "U_ALICE",
      approver_slack_id: nil,
      target_group: "group:tuist-prod-write",
      intent: "Restart deploy/tuist-tuist-server in tuist namespace",
      ttl_seconds: 900,
      slack_channel_id: "C_APPROVALS",
      slack_message_ts: nil,
      expires_at: DateTime.add(DateTime.utc_now(), 600, :second)
    }
  end
end
