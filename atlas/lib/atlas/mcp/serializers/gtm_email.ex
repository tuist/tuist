defmodule Atlas.MCP.Serializers.GTMEmail do
  @moduledoc false

  alias Atlas.MCP.Tool

  def subscriber(subscriber) do
    %{
      id: subscriber.id,
      email: subscriber.email,
      first_name: subscriber.first_name,
      last_name: subscriber.last_name,
      user_group: subscriber.user_group,
      source: subscriber.source,
      status: subscriber.status,
      metadata: subscriber.metadata || %{},
      confirmed_at: Tool.iso8601(subscriber.confirmed_at),
      unsubscribed_at: Tool.iso8601(subscriber.unsubscribed_at),
      welcomed_at: Tool.iso8601(subscriber.welcomed_at),
      inserted_at: Tool.iso8601(subscriber.inserted_at),
      updated_at: Tool.iso8601(subscriber.updated_at)
    }
  end

  def subscriber_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "email" => %{"type" => "string"},
        "first_name" => nullable_string(),
        "last_name" => nullable_string(),
        "user_group" => nullable_string(),
        "source" => %{"type" => "string"},
        "status" => %{"type" => "string"},
        "metadata" => %{"type" => "object"},
        "confirmed_at" => nullable_string(),
        "unsubscribed_at" => nullable_string(),
        "welcomed_at" => nullable_string(),
        "inserted_at" => nullable_string(),
        "updated_at" => nullable_string()
      },
      "required" =>
        ~w(id email first_name last_name user_group source status metadata confirmed_at unsubscribed_at welcomed_at inserted_at updated_at),
      "additionalProperties" => false
    }
  end

  def audience(audience) do
    %{
      id: audience.id,
      name: audience.name,
      slug: audience.slug,
      description: audience.description,
      membership_type: audience.membership_type,
      rules: audience.rules || %{},
      subscribers_count: audience_subscribers_count(audience),
      broadcasts_count: audience_broadcasts_count(audience),
      inserted_at: Tool.iso8601(audience.inserted_at),
      updated_at: Tool.iso8601(audience.updated_at)
    }
  end

  def audience_with_members(audience) do
    audience
    |> audience()
    |> Map.put(
      :members,
      if(Ecto.assoc_loaded?(audience.memberships),
        do: Enum.map(audience.memberships, &membership/1),
        else: []
      )
    )
    |> Map.put(
      :broadcasts,
      if(Ecto.assoc_loaded?(audience.broadcasts),
        do: Enum.map(audience.broadcasts, &broadcast/1),
        else: []
      )
    )
  end

  def audience_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "name" => %{"type" => "string"},
        "slug" => %{"type" => "string"},
        "description" => nullable_string(),
        "membership_type" => %{"type" => "string", "enum" => ["static", "dynamic"]},
        "rules" => %{"type" => "object"},
        "subscribers_count" => %{"type" => "integer"},
        "broadcasts_count" => %{"type" => "integer"},
        "inserted_at" => nullable_string(),
        "updated_at" => nullable_string()
      },
      "required" =>
        ~w(id name slug description membership_type rules subscribers_count broadcasts_count inserted_at updated_at),
      "additionalProperties" => false
    }
  end

  def audience_with_members_schema do
    base = audience_schema()

    %{
      base
      | "properties" =>
          base["properties"]
          |> Map.put("members", %{"type" => "array", "items" => membership_schema()})
          |> Map.put("broadcasts", %{"type" => "array", "items" => broadcast_schema()}),
        "required" => base["required"] ++ ["members", "broadcasts"]
    }
  end

  def membership(membership) do
    %{
      id: membership.id,
      status: membership.status,
      unsubscribed_at: Tool.iso8601(membership.unsubscribed_at),
      subscriber: subscriber(membership.subscriber)
    }
  end

  def membership_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "status" => %{"type" => "string"},
        "unsubscribed_at" => nullable_string(),
        "subscriber" => subscriber_schema()
      },
      "required" => ~w(id status unsubscribed_at subscriber),
      "additionalProperties" => false
    }
  end

  def broadcast(broadcast) do
    %{
      id: broadcast.id,
      audience_id: broadcast.audience_id,
      subject: broadcast.subject,
      body_markdown: broadcast.body_markdown,
      from_name: broadcast.from_name,
      from_email: broadcast.from_email,
      reply_to_email: broadcast.reply_to_email,
      status: broadcast.status,
      recipients_count: broadcast.recipients_count,
      delivered_count: broadcast.delivered_count,
      failed_count: broadcast.failed_count,
      skipped_count: broadcast.skipped_count,
      sent_at: Tool.iso8601(broadcast.sent_at),
      inserted_at: Tool.iso8601(broadcast.inserted_at)
    }
  end

  def broadcast_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "audience_id" => %{"type" => "string"},
        "subject" => %{"type" => "string"},
        "body_markdown" => %{"type" => "string"},
        "from_name" => %{"type" => "string"},
        "from_email" => %{"type" => "string"},
        "reply_to_email" => nullable_string(),
        "status" => %{"type" => "string"},
        "recipients_count" => %{"type" => "integer"},
        "delivered_count" => %{"type" => "integer"},
        "failed_count" => %{"type" => "integer"},
        "skipped_count" => %{"type" => "integer"},
        "sent_at" => nullable_string(),
        "inserted_at" => nullable_string()
      },
      "required" =>
        ~w(id audience_id subject body_markdown from_name from_email reply_to_email status recipients_count delivered_count failed_count skipped_count sent_at inserted_at),
      "additionalProperties" => false
    }
  end

  def delivery(delivery) do
    metadata = delivery.metadata || %{}

    %{
      id: delivery.id,
      kind: delivery.kind,
      recipient_email: delivery.recipient_email,
      recipient_name: delivery.recipient_name,
      subject: delivery.subject,
      status: delivery.status,
      account_id: metadata["account_id"],
      account_key: metadata["account_key"],
      provider_message_id: delivery.provider_message_id,
      error: delivery.error,
      attempts: delivery.attempts,
      delivered_at: Tool.iso8601(delivery.delivered_at),
      inserted_at: Tool.iso8601(delivery.inserted_at)
    }
  end

  def delivery_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "kind" => %{"type" => "string"},
        "recipient_email" => %{"type" => "string"},
        "recipient_name" => nullable_string(),
        "subject" => %{"type" => "string"},
        "status" => %{"type" => "string"},
        "account_id" => nullable_string(),
        "account_key" => nullable_string(),
        "provider_message_id" => nullable_string(),
        "error" => nullable_string(),
        "attempts" => %{"type" => "integer"},
        "delivered_at" => nullable_string(),
        "inserted_at" => nullable_string()
      },
      "required" =>
        ~w(id kind recipient_email recipient_name subject status account_id account_key provider_message_id error attempts delivered_at inserted_at),
      "additionalProperties" => false
    }
  end

  def list_schema(key, item_schema, include_total_count \\ false) do
    properties = %{
      to_string(key) => %{"type" => "array", "items" => item_schema},
      "count" => %{"type" => "integer"}
    }

    {properties, required} =
      if include_total_count do
        {Map.put(properties, "total_count", %{"type" => "integer"}), [to_string(key), "count", "total_count"]}
      else
        {properties, [to_string(key), "count"]}
      end

    %{
      "type" => "object",
      "properties" => properties,
      "required" => required,
      "additionalProperties" => false
    }
  end

  defp audience_subscribers_count(audience) do
    if Ecto.assoc_loaded?(audience.memberships) do
      Enum.count(audience.memberships, &(&1.status == "subscribed"))
    else
      audience.subscribers_count || 0
    end
  end

  defp audience_broadcasts_count(audience) do
    if Ecto.assoc_loaded?(audience.broadcasts), do: length(audience.broadcasts), else: audience.broadcasts_count || 0
  end

  defp nullable_string, do: %{"type" => ["string", "null"]}
end
