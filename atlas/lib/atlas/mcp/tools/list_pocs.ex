defmodule Atlas.MCP.Tools.ListPOCs do
  @moduledoc "Lists POCs, optionally filtered by account."

  use Atlas.MCP.Tool,
    name: "list_pocs",
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_id" => %{"type" => "string", "description" => "Restrict to one account."},
        "status" => %{
          "type" => "string",
          "enum" => Atlas.Accounts.POCs.POC.statuses(),
          "description" => "Restrict to one status."
        }
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "pocs" => %{
          "type" => "array",
          "items" => Atlas.MCP.Tools.POCSerializers.poc_schema()
        }
      },
      "required" => ["pocs"],
      "additionalProperties" => false
    }

  alias Atlas.Accounts.POCs
  alias Atlas.MCP.Tools.POCSerializers

  @impl EMCP.Tool
  def description, do: "List POCs. Filter by account_id or status."

  def execute(_conn, args) do
    opts =
      []
      |> maybe_put(:account_id, Map.get(args, "account_id"))
      |> maybe_put(:status, Map.get(args, "status"))

    pocs = opts |> POCs.list_pocs() |> Enum.map(&POCSerializers.poc/1)
    {:ok, %{"pocs" => pocs}}
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, _key, ""), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
