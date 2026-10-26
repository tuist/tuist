defmodule Atlas.MCP.Tools.UpdateMyProfile do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "update_my_profile",
    schema: %{
      "type" => "object",
      "properties" => %{
        "description" => %{
          "type" => "string",
          "maxLength" => 4000,
          "description" => "Your role, personality and communication preferences. Empty text clears it."
        }
      },
      "required" => ["description"],
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"description" => %{"type" => "string", "maxLength" => 4000}},
      "required" => ["description"],
      "additionalProperties" => false
    }

  alias Atlas.MCP.Tool
  alias Atlas.Users

  @impl EMCP.Tool
  def description do
    "Replace only the authenticated caller's self-description (4000 Unicode characters / 16000 UTF-8 bytes). " <>
      "Use only when explicitly asked; do not infer or silently save personal traits. " <>
      "Pip uses this untrusted background only in private conversations, never shared threads. " <>
      "The text passes through this MCP client; prefer the native Profile editor for private entry."
  end

  def execute(conn, %{"description" => description} = args) when map_size(args) == 1 do
    with :ok <- Tool.authorize_authenticated(conn, "Your profile") do
      case Users.update_my_profile(Tool.current_user(conn), description) do
        {:ok, user} -> {:ok, %{description: user.description}}
        {:error, _reason} -> {:error, "Supply only description: up to 4000 Unicode characters and 16000 UTF-8 bytes."}
      end
    end
  end

  def execute(_conn, _args),
    do: {:error, "Supply only your description. No user selector or identity fields are accepted."}
end
