defmodule Atlas.MCP.Tools.CreateEmailSubscriber do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "create_email_subscriber",
    schema: %{
      "type" => "object",
      "required" => ["email"],
      "properties" => %{
        "email" => %{"type" => "string"},
        "first_name" => %{"type" => "string"},
        "last_name" => %{"type" => "string"},
        "user_group" => %{"type" => "string"},
        "source" => %{"type" => "string"},
        "status" => %{"type" => "string", "enum" => ["pending", "subscribed", "unsubscribed"]},
        "metadata" => %{"type" => "object"}
      }
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"subscriber" => Atlas.MCP.Serializers.GTMEmail.subscriber_schema()},
      "required" => ["subscriber"],
      "additionalProperties" => false
    }

  alias Atlas.GTM
  alias Atlas.MCP.Serializers.GTMEmail
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description, do: "Create an Atlas email subscriber. This does not add the subscriber to an audience."

  def execute(conn, args) do
    attrs = Map.take(args, ~w(email first_name last_name user_group source status metadata))

    case GTM.create_email_subscriber(attrs, Tool.current_user(conn)) do
      {:ok, subscriber} -> {:ok, %{subscriber: GTMEmail.subscriber(subscriber)}}
      {:error, changeset} -> {:error, "Could not create subscriber: #{Tool.format_changeset_errors(changeset)}"}
    end
  end
end
