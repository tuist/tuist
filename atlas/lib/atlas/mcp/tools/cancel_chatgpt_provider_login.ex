defmodule Atlas.MCP.Tools.CancelChatGPTProviderLogin do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "cancel_chatgpt_provider_login",
    schema: %{
      "type" => "object",
      "properties" => %{"login_id" => %{"type" => "string"}},
      "required" => ["login_id"],
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"status" => %{"type" => "string", "enum" => ["cancelled"]}},
      "required" => ["status"],
      "additionalProperties" => false
    }

  alias Atlas.LLMs.Connections
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Cancel the current user's pending ChatGPT device sign-in using its login_id. " <>
      "Preserves any previously saved ChatGPT connection. To delete saved credentials too, use disconnect_llm_provider."
  end

  def execute(conn, %{"login_id" => login_id}) do
    with :ok <- Tool.authorize_authenticated(conn, "Personal AI providers") do
      case Connections.cancel_chatgpt(Tool.current_user(conn), login_id) do
        {:ok, status} ->
          {:ok, status}

        {:error, _reason} ->
          {:error, "Could not cancel ChatGPT sign-in. No matching pending login may exist for the current user."}
      end
    end
  end

  def execute(_conn, _args), do: {:error, "A ChatGPT login_id is required."}
end
