defmodule Atlas.MCP.Tools.PollChatGPTProviderLogin do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "poll_chatgpt_provider_login",
    schema: %{
      "type" => "object",
      "properties" => %{"login_id" => %{"type" => "string"}},
      "required" => ["login_id"],
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"status" => %{"type" => "string", "enum" => ["pending", "connected"]}},
      "required" => ["status"],
      "additionalProperties" => false
    }

  alias Atlas.LLMs.Connections
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Poll the current user's ChatGPT sign-in using the login_id returned by start_chatgpt_provider_login. " <>
      "Wait at least its interval seconds between calls and stop when connected. " <>
      "Atlas saves or replaces credentials internally on success; the result contains only status, never provider tokens."
  end

  def execute(conn, %{"login_id" => login_id}) do
    with :ok <- Tool.authorize_authenticated(conn, "Personal AI providers") do
      case Connections.poll_chatgpt(Tool.current_user(conn), login_id) do
        {:ok, status} ->
          {:ok, status}

        {:error, :not_found} ->
          {:error, "No matching ChatGPT sign-in exists for the current user. Start a new sign-in."}

        {:error, :login_expired} ->
          {:error, "ChatGPT sign-in expired. Start a new sign-in."}

        {:error, :provider_unavailable} ->
          {:error, "ChatGPT is temporarily unavailable. Wait the polling interval and retry this login."}

        {:error, _reason} ->
          {:error, "ChatGPT sign-in did not complete. Start a new sign-in."}
      end
    end
  end

  def execute(_conn, _args), do: {:error, "A ChatGPT login_id is required."}
end
