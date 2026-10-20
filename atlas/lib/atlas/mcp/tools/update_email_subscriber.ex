defmodule Atlas.MCP.Tools.UpdateEmailSubscriber do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "update_email_subscriber",
    schema: %{
      "type" => "object",
      "required" => ["subscriber_id"],
      "properties" => %{
        "subscriber_id" => %{"type" => "string"},
        "email" => %{"type" => "string"},
        "first_name" => %{"type" => ["string", "null"]},
        "last_name" => %{"type" => ["string", "null"]},
        "user_group" => %{"type" => ["string", "null"]},
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
  def description, do: "Update the profile or subscription status of an Atlas email subscriber."

  def execute(conn, args) do
    with subscriber when not is_nil(subscriber) <- GTM.get_email_subscriber(args["subscriber_id"]),
         attrs = Map.take(args, ~w(email first_name last_name user_group source status metadata)),
         {:ok, updated} <- GTM.update_email_subscriber(subscriber, attrs, Tool.current_user(conn)) do
      {:ok, %{subscriber: GTMEmail.subscriber(updated)}}
    else
      nil -> {:error, "Email subscriber not found."}
      {:error, changeset} -> {:error, "Could not update subscriber: #{Tool.format_changeset_errors(changeset)}"}
    end
  end
end
