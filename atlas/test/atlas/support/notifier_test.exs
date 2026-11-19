defmodule Atlas.Support.NotifierTest do
  use Atlas.DataCase, async: true
  use Mimic

  alias Atlas.Audit.Activity
  alias Atlas.Repo
  alias Atlas.Slack.API
  alias Atlas.Support.Config
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

  test "does not post no-action inbound email or chats to Slack" do
    reject(&API.find_message_by_metadata/4)
    reject(&API.post_message/5)
    thread = %{thread() | action_needed: false, status: "resolved"}

    for event <- ["inbound_received", "chat_received"] do
      assert :silenced = Notifier.notify(thread, event, notification_id: Ecto.UUID.generate())
    end
  end

  test "audits a rejected support post and leaves it for Oban to retry" do
    stub(Config, :slack_channel_id, fn -> "C-SUPPORT" end)
    stub(API, :find_message_by_metadata, fn :company, "C-SUPPORT", _, _ -> {:ok, nil} end)

    expect(API, :post_message, fn :company, "C-SUPPORT", _, _, _ ->
      {:error, {:unexpected_response, 503, "private response body"}}
    end)

    thread = thread()

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert {:error, {:unexpected_response, 503, _body}} =
                 Notifier.notify(thread, "inbound_received", notification_id: Ecto.UUID.generate())
      end)

    refute log =~ "private response body"
    activity = Repo.one!(from(a in Activity, where: a.action == "support.notification_failed"))
    assert activity.target_id == thread.id
    assert activity.metadata["reason"] == "slack_delivery_failed"
    assert activity.metadata["slack_channel_id"] == "C-SUPPORT"
  end

  test "team-side events stay in support even when the thread needs no action" do
    stub(Config, :slack_channel_id, fn -> "C-SUPPORT" end)
    expect(API, :find_message_by_metadata, fn :company, "C-SUPPORT", _, _ -> {:ok, nil} end)

    expect(API, :post_message, fn :company, "C-SUPPORT", _, _, _ ->
      {:ok, %{"channel" => "C-SUPPORT", "ts" => "1724515200.000100"}}
    end)

    assert {:ok, %{channel_id: "C-SUPPORT"}} =
             Notifier.notify(%{thread() | action_needed: false}, "status_changed",
               status: "resolved",
               notification_id: Ecto.UUID.generate()
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

  test "shows where agent feedback was reported from" do
    notification_id = Ecto.UUID.generate()
    stub(API, :find_message_by_metadata, fn _workspace, _channel, _type, _id -> {:ok, nil} end)

    expect(API, :post_message, fn :company, "C-SUPPORT", _text, blocks, _opts ->
      assert Enum.any?(blocks, &((get_in(&1, ["text", "text"]) || "") =~ "acme/ios · maya · Example MCP"))
      {:ok, %{"channel" => "C-SUPPORT", "ts" => "1724515200.000100"}}
    end)

    thread = %{
      thread()
      | metadata: %{
          "channel" => "agent_feedback",
          "source" => "Example MCP",
          "reporter_handle" => "maya",
          "account_handle" => "acme",
          "project_handle" => "ios"
        }
    }

    assert {:ok, _post} =
             Notifier.notify(thread, "agent_feedback_received",
               channel_id: "C-SUPPORT",
               notification_id: notification_id,
               message: %Message{body: "The branch filter was ignored."}
             )
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
