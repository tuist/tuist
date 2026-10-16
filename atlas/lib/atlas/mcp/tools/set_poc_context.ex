defmodule Atlas.MCP.Tools.SetPOCContext do
  @moduledoc "Sets the structured context on a POC (developer count, CI, git forge, hosting notes)."

  use Atlas.MCP.Tool,
    name: "set_poc_context",
    schema: %{
      "type" => "object",
      "required" => ["poc_id"],
      "properties" => %{
        "poc_id" => %{"type" => "string"},
        "developer_count" => %{"type" => "integer", "minimum" => 0},
        "ci_solution" => %{
          "type" => "string",
          "enum" => Atlas.Accounts.POCs.Context.ci_solutions()
        },
        "git_forge" => %{
          "type" => "string",
          "enum" => Atlas.Accounts.POCs.Context.git_forges()
        },
        "primary_language" => %{
          "type" => "string",
          "enum" => Atlas.Accounts.POCs.Context.primary_languages()
        },
        "monorepo" => %{"type" => "boolean"},
        "notes" => %{"type" => "string"}
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"poc" => Atlas.MCP.Tools.POCSerializers.poc_schema()},
      "required" => ["poc"],
      "additionalProperties" => false
    }

  alias Atlas.Accounts.POCs
  alias Atlas.MCP.Tool
  alias Atlas.MCP.Tools.POCSerializers

  @impl EMCP.Tool
  def description, do: "Upsert the structured context on a POC. Authenticated operators only."

  def execute(conn, %{"poc_id" => poc_id} = args) do
    user = Tool.current_user(conn)

    case POCs.get_poc(poc_id) do
      nil ->
        {:error, "POC not found."}

      poc ->
        attrs =
          Map.take(args, [
            "developer_count",
            "ci_solution",
            "git_forge",
            "primary_language",
            "monorepo",
            "notes"
          ])

        case POCs.upsert_context(poc, attrs, user) do
          {:ok, _context} ->
            {:ok, %{"poc" => POCSerializers.poc(POCs.get_poc!(poc.id))}}

          {:error, :unauthorized} ->
            {:error, "Only authenticated operators can update POC context."}

          {:error, changeset} ->
            {:error, "Could not update POC context: #{Tool.format_changeset_errors(changeset)}"}
        end
    end
  end
end
