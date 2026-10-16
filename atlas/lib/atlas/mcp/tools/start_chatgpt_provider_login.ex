defmodule Atlas.MCP.Tools.StartChatGPTProviderLogin do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "start_chatgpt_provider_login",
    schema: %{"type" => "object", "properties" => %{}, "additionalProperties" => false},
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "login_id" => %{"type" => "string"},
        "user_code" => %{"type" => "string"},
        "verification_url" => %{"type" => "string"},
        "interval" => %{"type" => "integer"},
        "expires_at" => %{"type" => "string"}
      },
      "required" => ["login_id", "user_code", "verification_url", "interval", "expires_at"],
      "additionalProperties" => false
    }

  alias Atlas.LLMs.Connections
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Start or replace the current user's personal ChatGPT connection through device sign-in. " <>
      "Requires Atlas's operator-configured OAuth client. Show the verification URL and one-time code to the user; " <>
      "only the user may authorize it on OpenAI's website. Poll using poll_chatgpt_provider_login no faster than interval seconds. " <>
      "Expires after 15 minutes. Cancel an existing pending login before starting another. " <>
      "Saved credentials stay unchanged until sign-in succeeds. Never asks for a password or returns provider tokens."
  end

  def execute(conn, _args) do
    with :ok <- Tool.authorize_authenticated(conn, "Personal AI providers") do
      case Connections.start_chatgpt(Tool.current_user(conn)) do
        {:ok, login} ->
          {:ok, login}

        {:error, :chatgpt_not_configured} ->
          {:error,
           "ChatGPT sign-in is not enabled. Ask your Atlas administrator to configure an authorized OAuth client."}

        {:error, :login_in_progress} ->
          {:error, "A ChatGPT sign-in is already pending. Finish it, cancel it, or wait for it to expire."}

        {:error, :rate_limited} ->
          {:error, "Too many ChatGPT sign-in attempts. Wait five minutes before trying again."}

        {:error, _reason} ->
          {:error, "Could not start ChatGPT sign-in. Please try again later."}
      end
    end
  end
end
