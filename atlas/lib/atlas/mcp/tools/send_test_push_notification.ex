defmodule Atlas.MCP.Tools.SendTestPushNotification do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "send_test_push_notification",
    schema: %{"type" => "object", "properties" => %{}, "additionalProperties" => false},
    output_schema: %{
      "type" => "object",
      "properties" => %{"queued" => %{"type" => "integer", "minimum" => 0}},
      "required" => ["queued"],
      "additionalProperties" => false
    }

  alias Atlas.MCP.Tool
  alias Atlas.Push
  alias Atlas.RateLimit

  @window :timer.minutes(10)
  @limit 5

  @impl EMCP.Tool
  def description do
    "Send the generic Atlas test notification to the current user's own registered phones. " <>
      "It opens Profile when tapped. Returns how many deliveries were queued; 0 means no phone " <>
      "has enabled notifications for this server. It cannot target other users or customize text."
  end

  def execute(conn, args) when map_size(args) == 0 do
    with :ok <- Tool.authorize_authenticated(conn, "Push notifications"),
         user = Tool.current_user(conn),
         {:allow, _attempts} <- RateLimit.hit("push_self_test:#{user.id}", @window, @limit),
         {:ok, queued} <- Push.notify_user(user.id, "self_test", {"profile", nil}) do
      {:ok, %{queued: queued}}
    else
      {:deny, _remaining} -> {:error, "Too many test notifications. Try again in a few minutes."}
      {:error, message} when is_binary(message) -> {:error, message}
      {:error, _reason} -> {:error, "Could not queue a test notification."}
    end
  end

  def execute(_conn, _args), do: {:error, "This tool takes no arguments."}
end
