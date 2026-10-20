defmodule Atlas.MCP.Tools.UnsubscribeEmailAudienceSubscriber do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "unsubscribe_email_audience_subscriber",
    schema: %{
      "type" => "object",
      "required" => ["audience_id", "subscriber_id"],
      "properties" => %{
        "audience_id" => %{"type" => "string"},
        "subscriber_id" => %{"type" => "string"}
      }
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"audience" => Atlas.MCP.Serializers.GTMEmail.audience_with_members_schema()},
      "required" => ["audience"],
      "additionalProperties" => false
    }

  alias Atlas.GTM
  alias Atlas.MCP.Serializers.GTMEmail
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description, do: "Unsubscribe an email subscriber from one Atlas audience."

  def execute(conn, args) do
    audience = GTM.get_email_audience(args["audience_id"])
    subscriber = GTM.get_email_subscriber(args["subscriber_id"])

    with audience when not is_nil(audience) <- audience,
         subscriber when not is_nil(subscriber) <- subscriber,
         {:ok, _membership} <-
           GTM.unsubscribe_email_audience_subscriber(audience, subscriber, Tool.current_user(conn)) do
      {:ok, %{audience: audience.id |> GTM.get_email_audience() |> GTMEmail.audience_with_members()}}
    else
      nil -> {:error, "Email audience or subscriber not found."}
      {:error, reason} -> {:error, "Could not unsubscribe subscriber: #{inspect(reason)}"}
    end
  end
end
