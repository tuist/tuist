defmodule Atlas.MCP.Tools.ListAccountServiceLevels do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "list_account_service_levels",
    schema: %{
      "type" => "object",
      "description" => "Provide one of account_id, account_key, or handle.",
      "properties" =>
        %{
          "active_on" => %{
            "type" => "string",
            "description" => "Optional YYYY-MM-DD date to return service levels active on that date."
          },
          "page_size" => %{"type" => "integer", "minimum" => 1, "maximum" => 100}
        }
        |> Map.merge(Atlas.MCP.AccountLookup.identifier_schema_properties())
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "account" => Atlas.MCP.Serializers.Accounts.related_account_schema(),
        "service_levels" => %{
          "type" => "array",
          "items" => Atlas.MCP.Serializers.Accounts.service_level_schema()
        },
        "service_level_extraction_checks" => %{
          "type" => "array",
          "items" => Atlas.MCP.Serializers.Accounts.service_level_extraction_check_schema()
        },
        "count" => %{"type" => "integer"}
      },
      "required" => ["account", "service_levels", "service_level_extraction_checks", "count"],
      "additionalProperties" => false
    }

  alias Atlas.Accounts
  alias Atlas.MCP.AccountLookup
  alias Atlas.MCP.Serializers.Accounts, as: AccountSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "List service levels extracted from signed account documents, including source document references and extraction check status."
  end

  def execute(_conn, args) do
    with {:ok, account} <- AccountLookup.resolve(args),
         {:ok, active_on} <- parse_active_on(args["active_on"]) do
      service_levels =
        account
        |> Accounts.list_service_levels(active_on: active_on)
        |> Enum.take(Tool.page_size(args))
        |> Enum.map(&AccountSerializer.service_level/1)

      checks =
        account
        |> Accounts.list_service_level_extraction_checks(limit: 5)
        |> Enum.map(&AccountSerializer.service_level_extraction_check/1)

      {:ok,
       %{
         account: AccountSerializer.related_account(account),
         service_levels: service_levels,
         service_level_extraction_checks: checks,
         count: length(service_levels)
       }}
    end
  end

  defp parse_active_on(nil), do: {:ok, nil}
  defp parse_active_on(""), do: {:ok, nil}

  defp parse_active_on(value) when is_binary(value) do
    case Date.from_iso8601(String.trim(value)) do
      {:ok, date} -> {:ok, date}
      {:error, _reason} -> {:error, "active_on must be a YYYY-MM-DD date."}
    end
  end

  defp parse_active_on(_value), do: {:error, "active_on must be a YYYY-MM-DD date."}
end
