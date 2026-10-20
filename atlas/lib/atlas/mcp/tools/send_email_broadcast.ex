defmodule Atlas.MCP.Tools.SendEmailBroadcast do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "send_email_broadcast",
    schema: %{
      "type" => "object",
      "required" => ["audience_id", "subject", "body_markdown"],
      "properties" => %{
        "audience_id" => %{"type" => "string"},
        "subject" => %{"type" => "string"},
        "body_markdown" => %{"type" => "string"},
        "from_name" => %{"type" => "string"},
        "from_email" => %{"type" => "string"},
        "reply_to_email" => %{"type" => "string"}
      }
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"broadcast" => Atlas.MCP.Serializers.GTMEmail.broadcast_schema()},
      "required" => ["broadcast"],
      "additionalProperties" => false
    }

  alias Atlas.GTM
  alias Atlas.MCP.Serializers.GTMEmail
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Immediately queue an email broadcast to a subscribed Atlas audience. This creates a fixed delivery record for every current recipient."
  end

  def execute(conn, args) do
    with audience when not is_nil(audience) <- GTM.get_email_audience(args["audience_id"]),
         attrs = Map.take(args, ~w(subject body_markdown from_name from_email reply_to_email)),
         {:ok, broadcast} <- GTM.queue_email_broadcast(audience, attrs, Tool.current_user(conn)) do
      {:ok, %{broadcast: GTMEmail.broadcast(broadcast)}}
    else
      nil ->
        {:error, "Email audience not found."}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, "Could not queue broadcast: #{Tool.format_changeset_errors(changeset)}"}

      {:error, reason} ->
        {:error, "Could not queue broadcast: #{inspect(reason)}"}
    end
  end
end
