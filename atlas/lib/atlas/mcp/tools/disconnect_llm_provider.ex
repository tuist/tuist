defmodule Atlas.MCP.Tools.DisconnectLLMProvider do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "disconnect_llm_provider",
    schema: %{
      "type" => "object",
      "properties" => %{"provider" => %{"type" => "string", "enum" => ["claude", "chatgpt"]}},
      "required" => ["provider"],
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"disconnected" => %{"type" => "boolean"}},
      "required" => ["disconnected"],
      "additionalProperties" => false
    }

  alias Atlas.LLMs.Connections
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Delete the current user's saved Claude or ChatGPT credentials and any pending login from Atlas. " <>
      "Does not revoke access at the provider. Never accepts another user's ID."
  end

  def execute(conn, %{"provider" => provider}) do
    with :ok <- Tool.authorize_authenticated(conn, "Personal AI providers"),
         {:ok, _metadata} <- Connections.disconnect(Tool.current_user(conn), provider) do
      {:ok, %{disconnected: true}}
    else
      {:error, _reason} -> {:error, "Could not disconnect the personal AI provider."}
    end
  end

  def execute(_conn, _args), do: {:error, "A provider is required."}
end
