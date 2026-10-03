defmodule Atlas.Support.NotifierTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Atlas.Slack.API
  alias Atlas.Support.Message
  alias Atlas.Support.Notifier
  alias Atlas.Support.Thread
  alias Atlas.Users.User

  setup :verify_on_exit!

  test "posts an inbound email notification to the configured support channel" do
    notification_id = Ecto.UUID.generate()

    expect(API, :find_message_by_metadata, fn :company, "C-SUPPORT", "atlas_support_event", ^notification_id ->
      {:ok, nil}
    end)

    expect(API, :post_message, fn :company, "C-SUPPORT", text, blocks, opts ->
      assert text =~ "New support email"
      assert Enum.any?(blocks, &(get_in(&1, ["text", "text"]) == "New support email"))
      assert opts[:client_msg_id] == notification_id
      assert opts[:metadata].event_payload.key == notification_id
      {:ok, %{"channel" => "C-SUPPORT", "ts" => "1724515200.000100"}}
    end)

    assert {:ok, %{channel_id: "C-SUPPORT", ts: "1724515200.000100"}} =
             Notifier.notify(thread(), "inbound_received",
               channel_id: "C-SUPPORT",
               notification_id: notification_id,
               message: %Message{body: "The cache upload is still pending."}
             )
  end

  test "never includes the private note body in the notification" do
    blocks =
      Notifier.build_blocks(thread(), "note_added",
        notification_id: Ecto.UUID.generate(),
        actor: %User{name: "Alex Rivera", email: "alex@example.com"},
        message: %Message{body: "This must remain private."}
      )

    text = blocks |> inspect() |> String.downcase()

    assert text =~ "private note was added"
    refute text =~ "this must remain private"
  end

  defp thread do
    %Thread{
      id: Ecto.UUID.generate(),
      customer_name: "Maya Chen",
      customer_email: "maya@acme.example",
      subject: "Cache upload stalls",
      status: "open"
    }
  end
end
