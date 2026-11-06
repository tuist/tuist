defmodule Atlas.MCP.Tools.ListLLMProviderConnections do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "list_llm_provider_connections",
    schema: %{"type" => "object", "properties" => %{}, "additionalProperties" => false},
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "providers" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "provider" => %{"type" => "string"},
              "credential_configured" => %{"type" => "boolean"},
              "login_available" => %{"type" => "boolean"},
              "expires_at" => %{"type" => ["string", "null"]},
              "updated_at" => %{"type" => ["string", "null"]}
            },
            "required" => ["provider", "credential_configured", "login_available", "expires_at", "updated_at"],
            "additionalProperties" => false
          }
        }
      },
      "required" => ["providers"],
      "additionalProperties" => false
    }

  alias Atlas.LLMs.Connections
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "List the current user's personal Claude and ChatGPT connection metadata, never credentials. " <>
      "Credential configuration does not verify provider access. Use connect_claude_provider to create or update Claude, " <>
      "start_chatgpt_provider_login and poll_chatgpt_provider_login to create or update ChatGPT, " <>
      "or disconnect_llm_provider to remove a connection. Browser settings: /settings/llm-providers."
  end

  def execute(conn, _args) do
    with :ok <- Tool.authorize_authenticated(conn, "Personal AI providers") do
      {:ok, %{providers: Connections.list(Tool.current_user(conn))}}
    end
  end
end
