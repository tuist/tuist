defmodule Atlas.MCP.Tools.ListAccounts do
  @moduledoc """
  Lists accounts visible to the authenticated user, optionally filtered
  by lifecycle segment or free-text search.
  """

  use Atlas.MCP.Tool,
    name: "list_accounts",
    schema: %{
      "type" => "object",
      "properties" => %{
        "query" => %{
          "type" => "string",
          "description" => "Free-text search across name, domain, and handles."
        },
        "segment" => %{
          "type" => "string",
          "enum" => ["customer", "lead", "prospect"],
          "description" => "Filter by lifecycle segment."
        }
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
              "account_key" => %{"type" => "string"},
              "name" => %{"type" => ["string", "null"]},
              "segment" => %{"type" => ["string", "null"]},
              "hosting" => %{"type" => ["string", "null"]},
              "status" => %{"type" => ["string", "null"]},
              "primary_domain" => %{"type" => ["string", "null"]},
              "parent_account_id" => %{"type" => ["string", "null"]},
              "latest_activity_at" => %{"type" => ["string", "null"]}
            },
            "required" => [
              "id",
              "account_key",
              "name",
              "segment",
              "hosting",
              "status",
              "primary_domain",
              "parent_account_id",
              "latest_activity_at"
            ],
            "additionalProperties" => false
          }
        },
        "count" => %{"type" => "integer"}
      },
      "required" => ["accounts", "count"],
      "additionalProperties" => false
    }

  alias Atlas.Accounts.Query, as: AccountsQuery
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description, do: "List accounts in Atlas. Use to find an account_id or handle to drill into."

  def execute(_conn, args) do
    opts =
      [filters: collect_filters(args)]
      |> maybe_put_query(args)

    accounts =
      opts
      |> AccountsQuery.list_accounts()
      |> Enum.map(&serialize/1)

    {:ok, %{accounts: accounts, count: length(accounts)}}
  end

  defp collect_filters(args) do
    maybe_add_filter([], args, "segment", "lifecycle")
  end

  defp maybe_add_filter(filters, args, key, filter_id) do
    case Map.get(args, key) do
      v when is_binary(v) and v != "" -> [%{id: filter_id, operator: :==, value: v} | filters]
      _ -> filters
    end
  end

  defp maybe_put_query(opts, %{"query" => q}) when is_binary(q) and q != "", do: Keyword.put(opts, :query, q)
  defp maybe_put_query(opts, _), do: opts

  defp serialize(account) do
    %{
      id: account.id,
      account_key: account.account_key,
      name: account.name,
      segment: account.segment,
      hosting: account.hosting,
      status: account.status,
      primary_domain: account.primary_domain,
      parent_account_id: account.parent_account_id,
      latest_activity_at: Tool.iso8601(account.latest_activity_at)
    }
  end
end
