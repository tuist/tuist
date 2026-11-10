defmodule Atlas.MCP.Tools.ListAccountNudges do
  @moduledoc "Lists nudges for an account, newest first."

  use Atlas.MCP.Tool,
    name: "list_account_nudges",
    schema: %{
      "type" => "object",
      "properties" =>
        Map.put(Atlas.MCP.AccountLookup.identifier_schema_properties(), "state", %{
          "type" => "string",
          "enum" => ["pending_post", "proposed", "claimed", "dismissed", "expired"]
        }),
      "anyOf" => Enum.map(["account_id", "account_key", "handle"], &%{"required" => [&1]})
    },
    output_schema: Atlas.MCP.Serializers.Nudges.list_response_schema()

  alias Atlas.MCP.AccountLookup
  alias Atlas.MCP.Serializers.Nudges, as: NudgeSerializer
  alias Atlas.MCP.Tool
  alias Atlas.Nudges

  @impl EMCP.Tool
  def description do
    "List one account's nudges. Requires account_id, account_key, or handle; state alone is not sufficient. " <>
      "Use list_accounts to find the account first. Nudges are per-signal outreach proposals for a human to claim and send."
  end

  def execute(conn, args) do
    with :ok <- Tool.authorize_scope(conn, "accounts:read", "Nudge tools"),
         {:ok, account} <- AccountLookup.resolve(args) do
      states = if is_binary(args["state"]), do: [args["state"]]

      nudges =
        account
        |> Nudges.list_nudges(states: states)
        |> Enum.map(&NudgeSerializer.nudge/1)

      {:ok, NudgeSerializer.list_response(nudges)}
    end
  end
end
