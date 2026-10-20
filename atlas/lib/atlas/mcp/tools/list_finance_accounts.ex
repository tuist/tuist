defmodule Atlas.MCP.Tools.ListFinanceAccounts do
  @moduledoc """
  Lists normalized finance accounts in Atlas.
  """

  use Atlas.MCP.Tool,
    name: "list_finance_accounts",
    schema: %{
      "type" => "object",
      "properties" => %{
        "provider" => %{
          "type" => "string",
          "enum" => ["qonto", "mercury"],
          "description" => "Filter accounts by provider."
        },
        "atlas_account_key" => %{
          "type" => "string",
          "description" => "Filter accounts by the linked Atlas company account key."
        },
        "source_key" => %{
          "type" => "string",
          "description" => "Filter accounts by configured finance source key."
        },
        "currency" => %{
          "type" => "string",
          "description" => "Filter accounts by account currency, for example EUR or USD."
        },
        "query" => %{
          "type" => "string",
          "description" => "Free-text search across account name, IBAN, BIC, and source name."
        },
        "page_size" => %{"type" => "integer", "minimum" => 1, "maximum" => 100}
      }
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "accounts" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "id" => %{"type" => "string"},
              "provider" => %{"type" => ["string", "null"]},
              "external_id" => %{"type" => ["string", "null"]},
              "name" => %{"type" => ["string", "null"]},
              "account_type" => %{"type" => ["string", "null"]},
              "account_subtype" => %{"type" => ["string", "null"]},
              "currency" => %{"type" => ["string", "null"]},
              "iban" => %{"type" => ["string", "null"]},
              "bic" => %{"type" => ["string", "null"]},
              "main" => %{"type" => ["boolean", "null"]},
              "status" => %{"type" => ["string", "null"]},
              "balance_value" => %{"type" => ["string", "null"]},
              "balance_currency" => %{"type" => ["string", "null"]},
              "available_balance_value" => %{"type" => ["string", "null"]},
              "available_balance_currency" => %{"type" => ["string", "null"]},
              "transactions_synced_at" => %{"type" => ["string", "null"]},
              "refreshed_at" => %{"type" => ["string", "null"]},
              "metadata" => %{"type" => ["object", "null"]},
              "source" => %{
                "type" => "object",
                "properties" => %{
                  "id" => %{"type" => "string"},
                  "atlas_account" =>
                    Atlas.MCP.Tool.nullable(%{
                      "type" => "object",
                      "properties" => %{
                        "id" => %{"type" => "string"},
                        "account_key" => %{"type" => "string"},
                        "name" => %{"type" => ["string", "null"]}
                      },
                      "required" => ["id", "account_key", "name"],
                      "additionalProperties" => false
                    }),
                  "config_key" => %{"type" => ["string", "null"]},
                  "name" => %{"type" => ["string", "null"]},
                  "provider" => %{"type" => ["string", "null"]}
                },
                "required" => ["id", "atlas_account", "config_key", "name", "provider"],
                "additionalProperties" => false
              }
            },
            "required" => [
              "id",
              "provider",
              "external_id",
              "name",
              "account_type",
              "account_subtype",
              "currency",
              "iban",
              "bic",
              "main",
              "status",
              "balance_value",
              "balance_currency",
              "available_balance_value",
              "available_balance_currency",
              "transactions_synced_at",
              "refreshed_at",
              "metadata",
              "source"
            ],
            "additionalProperties" => false
          }
        },
        "count" => %{"type" => "integer"}
      },
      "required" => ["accounts", "count"],
      "additionalProperties" => false
    }

  alias Atlas.Finance
  alias Atlas.Finance.Account
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "List normalized finance accounts in Atlas. Use this to find account ids, currencies, balances, and source keys."
  end

  def execute(conn, args) do
    with :ok <- Tool.authorize_scope(conn, "finance:read", "Finance tools") do
      accounts =
        args
        |> list_opts()
        |> Finance.list_accounts()
        |> Enum.map(&serialize_account/1)

      {:ok, %{accounts: accounts, count: length(accounts)}}
    end
  end

  defp list_opts(args) do
    [
      limit: Tool.page_size(args),
      provider: present(args, "provider"),
      atlas_account_key: present(args, "atlas_account_key"),
      source_key: present(args, "source_key"),
      currency: present(args, "currency"),
      query: present(args, "query")
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp serialize_account(%Account{} = account) do
    %{
      id: account.id,
      provider: account.provider,
      external_id: account.external_id,
      name: account.name,
      account_type: account.account_type,
      account_subtype: account.account_subtype,
      currency: account.currency,
      iban: account.iban,
      bic: account.bic,
      main: account.main,
      status: account.status,
      balance_value: decimal_to_string(account.balance_value),
      balance_currency: account.balance_currency,
      available_balance_value: decimal_to_string(account.available_balance_value),
      available_balance_currency: account.available_balance_currency,
      transactions_synced_at: Tool.iso8601(account.transactions_synced_at),
      refreshed_at: Tool.iso8601(account.refreshed_at),
      metadata: account.metadata,
      source: %{
        id: account.source.id,
        atlas_account: serialize_atlas_account(account.source.atlas_account),
        config_key: account.source.config_key,
        name: account.source.name,
        provider: account.source.provider
      }
    }
  end

  defp serialize_atlas_account(nil), do: nil

  defp serialize_atlas_account(atlas_account) do
    %{
      id: atlas_account.id,
      account_key: atlas_account.account_key,
      name: atlas_account.name
    }
  end

  defp present(args, key) do
    case Map.get(args, key) do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp decimal_to_string(nil), do: nil
  defp decimal_to_string(value), do: Decimal.to_string(value)
end
