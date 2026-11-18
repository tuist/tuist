defmodule Atlas.MCP.Tools.GmailSerializers do
  @moduledoc false

  alias Atlas.MCP.Tools.ManageAccountConnections

  @draft_fields ~w(id message_id thread_id to cc bcc subject in_reply_to body attachments)a

  @doc "A Gmail message summary, optionally with extra required properties."
  def message_schema(extra \\ %{}) do
    %{
      "type" => "object",
      "required" => ["id", "thread_id", "from", "to", "subject", "date", "snippet", "labels"] ++ Map.keys(extra),
      "properties" =>
        Map.merge(
          %{
            "id" => %{"type" => "string"},
            "thread_id" => %{"type" => ["string", "null"]},
            "from" => %{"type" => "string"},
            "to" => %{"type" => "string"},
            "subject" => %{"type" => "string"},
            "date" => %{"type" => "string"},
            "snippet" => %{"type" => "string"},
            "labels" => %{"type" => "array", "items" => %{"type" => "string"}}
          },
          extra
        ),
      "additionalProperties" => false
    }
  end

  def message_attachments_schema do
    %{
      "type" => "array",
      "items" => %{
        "type" => "object",
        "required" => ["part_id", "filename", "mime_type", "size"],
        "properties" => %{
          "part_id" => %{"type" => "string"},
          "filename" => %{"type" => "string"},
          "mime_type" => %{"type" => ["string", "null"]},
          "size" => %{"type" => ["integer", "null"]}
        },
        "additionalProperties" => false
      }
    }
  end

  def draft_schema do
    %{
      "type" => "object",
      "required" => Enum.map(@draft_fields, &Atom.to_string/1),
      "properties" => %{
        "id" => %{"type" => "string"},
        "message_id" => %{"type" => ["string", "null"]},
        "thread_id" => %{"type" => ["string", "null"]},
        "to" => %{"type" => "string"},
        "cc" => %{"type" => "string"},
        "bcc" => %{"type" => "string"},
        "subject" => %{"type" => "string"},
        "in_reply_to" => %{"type" => ["string", "null"]},
        "body" => %{"type" => "string"},
        "attachments" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "required" => ["filename", "mime_type", "size"],
            "properties" => %{
              "filename" => %{"type" => "string"},
              "mime_type" => %{"type" => ["string", "null"]},
              "size" => %{"type" => ["integer", "null"]}
            },
            "additionalProperties" => false
          }
        }
      },
      "additionalProperties" => false
    }
  end

  @doc "Input properties shared by draft creation and replacement."
  def draft_input_properties do
    address = %{"type" => "string", "format" => "email", "maxLength" => 254}

    %{
      "to" => %{
        "type" => "array",
        "items" => address,
        "minItems" => 1,
        "maxItems" => 50,
        "description" => "Plain email addresses, without display names."
      },
      "cc" => %{"type" => "array", "items" => address, "maxItems" => 50},
      "subject" => %{"type" => "string", "maxLength" => 500, "description" => "One line."},
      "body" => %{"type" => "string", "description" => "Plain-text body, up to 100,000 bytes."},
      "reply_to_message_id" => %{
        "type" => "string",
        "description" =>
          "Message id from search_my_gmail to reply to. Sets threadId, In-Reply-To and References; keep the " <>
            "original subject (with Re:) so Gmail files it in the same conversation. Needs Gmail read access."
      }
    }
  end

  def draft(draft), do: Map.take(draft, @draft_fields)

  def validate(module, args) do
    case ExJsonSchema.Validator.validate(ExJsonSchema.Schema.resolve(module.input_schema()), args) do
      :ok -> :ok
      {:error, _errors} -> {:error, "Arguments do not match the #{module.name()} schema."}
    end
  end

  @doc "Caller-facing message for a failed Gmail tool call."
  def error({:error, :shared_identity}), do: {:error, "Personal Gmail is unavailable to shared Slack identities."}
  def error({:error, message}) when is_binary(message), do: {:error, message}

  def error({:error, :insufficient_scope}) do
    {:error,
     "Gmail drafts need Allow Gmail drafts at #{AtlasWeb.Endpoint.url()}/settings/connections " <>
       "(replies also need Allow Gmail access)."}
  end

  def error({:error, reason}), do: {:error, ManageAccountConnections.connection_error("Gmail", reason)}
end
