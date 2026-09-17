defmodule Atlas.MCP.Serializers.Letters do
  @moduledoc false

  alias Atlas.Letters.Letter
  alias Atlas.MCP.Tool

  def letter(%Letter{} = letter) do
    %{
      id: letter.id,
      kind: letter.kind,
      status: letter.status,
      subject: letter.subject,
      recipient: %{
        name: letter.recipient_name,
        street: letter.recipient_street,
        postal_code: letter.recipient_postal_code,
        city: letter.recipient_city,
        country: letter.recipient_country,
        reference: letter.recipient_reference
      },
      tracking_number: letter.pingen_tracking_number,
      delivery_status: letter.pingen_status,
      delivery_details: letter.delivery_details,
      delivery_prepared_at: Tool.iso8601(letter.delivery_prepared_at),
      confirmed_at: Tool.iso8601(letter.confirmed_at),
      sent_at: Tool.iso8601(letter.sent_at),
      delivered_at: Tool.iso8601(letter.delivered_at),
      undeliverable_at: Tool.iso8601(letter.undeliverable_at),
      last_checked_at: Tool.iso8601(letter.last_checked_at),
      document_url: if(letter.document, do: Tool.document_url(letter.document)),
      signed_document_url: if(letter.signed_document, do: Tool.document_url(letter.signed_document))
    }
  end

  def letter_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "kind" => %{"type" => "string"},
        "status" => %{"type" => "string"},
        "subject" => %{"type" => ["string", "null"]},
        "recipient" => %{
          "type" => "object",
          "properties" => %{
            "name" => %{"type" => ["string", "null"]},
            "street" => %{"type" => ["string", "null"]},
            "postal_code" => %{"type" => ["string", "null"]},
            "city" => %{"type" => ["string", "null"]},
            "country" => %{"type" => ["string", "null"]},
            "reference" => %{"type" => ["string", "null"]}
          },
          "required" => ["name", "street", "postal_code", "city", "country", "reference"],
          "additionalProperties" => false
        },
        "tracking_number" => %{"type" => ["string", "null"]},
        "delivery_status" => %{"type" => ["string", "null"]},
        "delivery_details" => %{"type" => ["object", "null"], "additionalProperties" => true},
        "delivery_prepared_at" => %{"type" => ["string", "null"]},
        "confirmed_at" => %{"type" => ["string", "null"]},
        "sent_at" => %{"type" => ["string", "null"]},
        "delivered_at" => %{"type" => ["string", "null"]},
        "undeliverable_at" => %{"type" => ["string", "null"]},
        "last_checked_at" => %{"type" => ["string", "null"]},
        "document_url" => %{"type" => ["string", "null"]},
        "signed_document_url" => %{"type" => ["string", "null"]}
      },
      "required" => [
        "id",
        "kind",
        "status",
        "subject",
        "recipient",
        "tracking_number",
        "delivery_status",
        "delivery_details",
        "delivery_prepared_at",
        "confirmed_at",
        "sent_at",
        "delivered_at",
        "undeliverable_at",
        "last_checked_at",
        "document_url",
        "signed_document_url"
      ],
      "additionalProperties" => false
    }
  end
end
