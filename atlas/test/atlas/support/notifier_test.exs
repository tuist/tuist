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

  test "routes no-action inbound to the filtered channel with its resolved status" do
    stub(Config, :slack_channel_id, fn -> "C-SUPPORT" end)
    stub(Config, :slack_filtered_channel_id, fn -> "C-FILTERED" end)
    notification_id = Ecto.UUID.generate()
    thread = %{thread() | action_needed: false, status: "resolved"}

    expect(API, :find_message_by_metadata, fn :company, "C-FILTERED", _, ^notification_id -> {:ok, nil} end)

    expect(API, :post_message, fn :company, "C-FILTERED", _, blocks, _ ->
      assert inspect(blocks) =~ "Resolved"
      {:ok, %{"channel" => "C-FILTERED", "ts" => "1724515200.000100"}}
    end)

    assert {:ok, %{channel_id: "C-FILTERED"}} =
             Notifier.notify(thread, "inbound_received", notification_id: notification_id)
  end

  test "falls back to support and audits an inaccessible filtered channel" do
    stub(Config, :slack_channel_id, fn -> "C-SUPPORT" end)
    stub(Config, :slack_filtered_channel_id, fn -> "C-FILTERED" end)
    notification_id = Ecto.UUID.generate()
    thread = %{thread() | action_needed: false}
    stub(API, :find_message_by_metadata, fn :company, _, _, ^notification_id -> {:ok, nil} end)

    expect(API, :post_message, fn :company, "C-FILTERED", _, _, _ -> {:error, "not_in_channel"} end)

    expect(API, :post_message, fn :company, "C-SUPPORT", _, _, opts ->
      assert opts[:client_msg_id] == notification_id
      {:ok, %{"channel" => "C-SUPPORT", "ts" => "1724515200.000100"}}
    end)

    assert {:ok, %{channel_id: "C-SUPPORT"}} =
             Notifier.notify(thread, "inbound_received", notification_id: notification_id)

    activity = Repo.one!(from(a in Activity, where: a.action == "support.notification_failed"))
    assert activity.target_id == thread.id
    assert activity.metadata["reason"] == "not_in_channel"
    assert activity.metadata["slack_channel_id"] == "C-FILTERED"
  end

  test "leaves transient filtered-channel failures for Oban to retry" do
    stub(Config, :slack_channel_id, fn -> "C-SUPPORT" end)
    stub(Config, :slack_filtered_channel_id, fn -> "C-FILTERED" end)
    stub(API, :find_message_by_metadata, fn :company, "C-FILTERED", _, _ -> {:ok, nil} end)
    expect(API, :post_message, fn :company, "C-FILTERED", _, _, _ -> {:error, :timeout} end)

    assert {:error, :timeout} =
             Notifier.notify(%{thread() | action_needed: false}, "inbound_received",
               notification_id: Ecto.UUID.generate()
             )
  end

  test "tries support on the last attempt even for an unknown filtered-channel failure" do
    stub(Config, :slack_channel_id, fn -> "C-SUPPORT" end)
    stub(Config, :slack_filtered_channel_id, fn -> "C-FILTERED" end)
    stub(API, :find_message_by_metadata, fn :company, _, _, _ -> {:ok, nil} end)

    expect(API, :post_message, fn :company, "C-FILTERED", _, _, _ ->
      {:error, {:unexpected_response, 503, "private response body"}}
    end)

    expect(API, :post_message, fn :company, "C-SUPPORT", _, _, _ ->
      {:ok, %{"channel" => "C-SUPPORT", "ts" => "1724515200.000100"}}
    end)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert {:ok, %{channel_id: "C-SUPPORT"}} =
                 Notifier.notify(%{thread() | action_needed: false}, "inbound_received",
                   notification_id: Ecto.UUID.generate(),
                   final_attempt?: true
                 )
      end)

    refute log =~ "private response body"
    activity = Repo.one!(from(a in Activity, where: a.action == "support.notification_failed"))
    assert activity.metadata["reason"] == "slack_delivery_failed"
    refute inspect(activity.metadata) =~ "private response body"
  end

  test "returns the fallback error without recursing when both channels reject the post" do
    stub(Config, :slack_channel_id, fn -> "C-SUPPORT" end)
    stub(Config, :slack_filtered_channel_id, fn -> "C-FILTERED" end)
    stub(API, :find_message_by_metadata, fn :company, _, _, _ -> {:ok, nil} end)
    expect(API, :post_message, fn :company, "C-FILTERED", _, _, _ -> {:error, "not_in_channel"} end)
    expect(API, :post_message, fn :company, "C-SUPPORT", _, _, _ -> {:error, "missing_scope"} end)

    assert {:error, "missing_scope"} =
             Notifier.notify(%{thread() | action_needed: false}, "inbound_received",
               notification_id: Ecto.UUID.generate(),
               final_attempt?: true
             )

    assert Repo.aggregate(from(a in Activity, where: a.action == "support.notification_failed"), :count) == 2
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
