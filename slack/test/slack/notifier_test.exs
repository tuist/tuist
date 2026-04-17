defmodule Slack.NotifierTest do
  use ExUnit.Case, async: false

  alias Slack.Notifier

  setup do
    original = Application.get_env(:slack, :notifier)
    on_exit(fn -> Application.put_env(:slack, :notifier, original) end)
    :ok
  end

  describe "enabled?/0" do
    test "is false when bot_token or channel_id is blank" do
      Application.put_env(:slack, :notifier, bot_token: nil, channel_id: nil)
      refute Notifier.enabled?()

      Application.put_env(:slack, :notifier, bot_token: "xoxb-test", channel_id: nil)
      refute Notifier.enabled?()
    end

    test "is true when both are set" do
      Application.put_env(:slack, :notifier, bot_token: "xoxb-test", channel_id: "C123")
      assert Notifier.enabled?()
    end
  end

  describe "invitation_confirmed/1" do
    test "no-ops when disabled" do
      Application.put_env(:slack, :notifier, bot_token: nil, channel_id: nil)

      invitation = %Slack.Invitations.Invitation{
        email: "test@tuist.dev",
        reason: "Just testing"
      }

      assert Notifier.invitation_confirmed(invitation) == :ok
    end
  end
end
