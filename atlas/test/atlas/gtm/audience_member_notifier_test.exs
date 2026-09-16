defmodule Atlas.GTM.AudienceMemberNotifierTest do
  use Atlas.DataCase, async: true
  use Mimic

  alias Atlas.GTM.AudienceMemberNotifier
  alias Atlas.GTM.Audiences
  alias Atlas.Slack.API

  setup :verify_on_exit!

  setup do
    {:ok, audience} = Audiences.create_audience(%{name: "Product users"})

    {:ok, subscriber} =
      Audiences.create_subscriber(
        %{
          email: "member@example.com",
          first_name: "Sam",
          last_name: "Builder",
          user_group: "developer",
          source: "posthog",
          metadata: %{"userId" => "user-123"}
        },
        nil,
        automations: false
      )

    %{audience: audience, subscriber: subscriber, notification_id: Ecto.UUID.generate()}
  end

  test "renders the audience member details and Atlas link", %{audience: audience, subscriber: subscriber} do
    blocks = AudienceMemberNotifier.build_blocks(audience, subscriber)

    assert get_in(Enum.at(blocks, 0), ["text", "text"]) == "New audience member"

    section = Enum.find(blocks, &(&1["type"] == "section"))

    field_text =
      section
      |> Map.fetch!("fields")
      |> Enum.map_join("\n", &get_in(&1, ["text"]))

    assert field_text =~ "Product users"
    assert field_text =~ "Sam Builder"
    assert field_text =~ "member@example.com"
    assert field_text =~ "posthog"
    assert field_text =~ "developer"
    assert field_text =~ "user-123"

    assert section["accessory"] == %{
             "type" => "image",
             "image_url" => "https://www.gravatar.com/avatar/a4fae232e2bfebd9f4dc8d7cb6caecb2?d=identicon&s=128",
             "alt_text" => "Sam Builder"
           }

    action = Enum.find(blocks, &(&1["type"] == "actions"))
    assert get_in(action, ["elements", Access.at(0), "url"]) =~ "/outbound/email/audiences/#{audience.id}"
  end

  test "reuses an existing Slack message when a retry can reconcile it", %{
    audience: audience,
    subscriber: subscriber,
    notification_id: notification_id
  } do
    expect(API, :find_message_by_metadata, fn
      :company, "C0AGV3YU8ET", "atlas_audience_member_added", ^notification_id ->
        {:ok, %{"channel" => "C0AGV3YU8ET", "ts" => "1717400000.000100"}}
    end)

    reject(&API.post_message/5)

    assert {:ok, %{"ts" => "1717400000.000100"}} =
             AudienceMemberNotifier.announce(audience, subscriber, notification_id)
  end

  test "posts a Blocks UI notification to the company gtm channel", %{
    audience: audience,
    subscriber: subscriber,
    notification_id: notification_id
  } do
    expect(API, :find_message_by_metadata, fn
      :company, "C0AGV3YU8ET", "atlas_audience_member_added", ^notification_id -> {:ok, nil}
    end)

    expect(API, :post_message, fn :company, "C0AGV3YU8ET", text, blocks, opts ->
      assert text =~ "Product users"
      assert Enum.any?(blocks, &(&1["type"] == "header"))
      assert Enum.any?(blocks, &(&1["type"] == "section"))
      assert Enum.any?(blocks, &(&1["type"] == "actions"))
      assert opts[:client_msg_id] == notification_id
      assert opts[:metadata].event_type == "atlas_audience_member_added"
      assert opts[:metadata].event_payload.key == notification_id
      {:ok, %{"channel" => "C0AGV3YU8ET", "ts" => "1717400000.000200"}}
    end)

    assert {:ok, %{"ts" => "1717400000.000200"}} =
             AudienceMemberNotifier.announce(audience, subscriber, notification_id)
  end

  test "posts when Slack history cannot be read", %{
    audience: audience,
    subscriber: subscriber,
    notification_id: notification_id
  } do
    expect(API, :find_message_by_metadata, fn
      :company, "C0AGV3YU8ET", "atlas_audience_member_added", ^notification_id ->
        {:error, "missing_scope"}
    end)

    expect(API, :post_message, fn :company, "C0AGV3YU8ET", _text, _blocks, _opts ->
      {:ok, %{"ts" => "1717400000.000300"}}
    end)

    assert {:ok, %{"ts" => "1717400000.000300"}} =
             AudienceMemberNotifier.announce(audience, subscriber, notification_id)
  end

  test "rejects a Slack response without a message timestamp", %{
    audience: audience,
    subscriber: subscriber,
    notification_id: notification_id
  } do
    expect(API, :find_message_by_metadata, fn
      :company, "C0AGV3YU8ET", "atlas_audience_member_added", ^notification_id -> {:ok, nil}
    end)

    expect(API, :post_message, fn :company, "C0AGV3YU8ET", _text, _blocks, _opts ->
      {:ok, %{"ok" => true}}
    end)

    assert {:error, :slack_audience_member_timestamp_missing} =
             AudienceMemberNotifier.announce(audience, subscriber, notification_id)
  end
end
