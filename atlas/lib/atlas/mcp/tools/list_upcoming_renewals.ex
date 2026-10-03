defmodule Atlas.MCP.Tools.ListUpcomingRenewals do
  @moduledoc """
  Lists active customer accounts with upcoming renewal dates.
  """

  use Atlas.MCP.Tool,
    name: "list_upcoming_renewals",
    schema: %{
      "type" => "object",
      "properties" => %{
        "page_size" => %{
          "type" => "integer",
          "minimum" => 1,
          "maximum" => 100,
          "description" => "Maximum number of renewals to return. Defaults to 20."
        }
      }
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "renewals" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "id" => %{"type" => "string"},
              "account_key" => %{"type" => "string"},
              "name" => %{"type" => ["string", "null"]},
              "primary_domain" => %{"type" => ["string", "null"]},
              "status" => %{"type" => ["string", "null"]},
              "currency" => %{"type" => ["string", "null"]},
              "current_value" => %{"type" => ["string", "null"]},
              "next_renewal_date" => %{"type" => ["string", "null"]},
              "url" => %{"type" => "string"}
            },
            "required" => [
              "id",
              "account_key",
              "name",
              "primary_domain",
              "status",
              "currency",
              "current_value",
              "next_renewal_date",
              "url"
            ],
            "additionalProperties" => false
          }
        },
        "count" => %{"type" => "integer"}
      },
      "required" => ["renewals", "count"],
      "additionalProperties" => false
    }

  alias Atlas.Accounts
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "List active customer renewals ordered by the nearest upcoming renewal date."
  end

  def execute(_conn, args) do
    renewals =
      [limit: Tool.page_size(args)]
      |> Accounts.list_upcoming_renewals()
      |> Enum.map(&serialize/1)

    {:ok, %{renewals: renewals, count: length(renewals)}}
  end

  defp serialize(account) do
    {current_value, currency} = Accounts.contract_value(account)

    %{
      id: account.id,
      account_key: account.account_key,
      name: account.name,
      primary_domain: account.primary_domain,
      status: account.status,
      currency: currency,
      current_value: current_value && Decimal.to_string(current_value),
      next_renewal_date: Tool.iso8601(account.next_renewal_date),
      url: Tool.account_url(account.id)
    }
  end
end
