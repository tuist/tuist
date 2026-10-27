defmodule Atlas.MCP.Tools.GetFinanceOverview do
  @moduledoc """
  Summarizes normalized finance data synced into Atlas.
  """

  use Atlas.MCP.Tool,
    name: "get_finance_overview",
    schema: %{
      "type" => "object",
      "properties" => %{}
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "overview" => %{
          "type" => "object",
          "properties" => %{
            "currency" => %{"type" => ["string", "null"]},
            "available_cash_value" => %{"type" => ["string", "null"]},
            "total_balance_value" => %{"type" => ["string", "null"]},
            "net_30d_value" => %{"type" => ["string", "null"]},
            "monthly_burn_value" => %{"type" => ["string", "null"]},
            "smoothed_monthly_burn_value" => %{"type" => ["string", "null"]},
            "runway_months" => %{"type" => ["string", "null"]},
            "trailing_cash_runway_months" => %{"type" => ["string", "null"]},
            "smoothed_cash_runway_months" => %{"type" => ["string", "null"]},
            "projected_monthly_revenue_value" => %{"type" => ["string", "null"]},
            "projected_arr_value" => %{"type" => ["string", "null"]},
            "projected_customer_count" => %{"type" => ["integer", "null"]},
            "projected_monthly_expenses_value" => %{"type" => ["string", "null"]},
            "projected_net_burn_value" => %{"type" => ["string", "null"]},
            "projected_runway_months" => %{"type" => ["string", "null"]},
            "plan_adjusted_monthly_burn_value" => %{"type" => ["string", "null"]},
            "plan_adjusted_runway_months" => %{"type" => ["string", "null"]},
            "runway_window_days" => %{"type" => ["integer", "null"]},
            "source_count" => %{"type" => "integer"},
            "account_count" => %{"type" => "integer"},
            "transaction_count_30d" => %{"type" => "integer"},
            "last_synced_at" => %{"type" => ["string", "null"]}
          },
          "required" => [
            "currency",
            "available_cash_value",
            "total_balance_value",
            "net_30d_value",
            "monthly_burn_value",
            "smoothed_monthly_burn_value",
            "runway_months",
            "trailing_cash_runway_months",
            "smoothed_cash_runway_months",
            "projected_monthly_revenue_value",
            "projected_arr_value",
            "projected_customer_count",
            "projected_monthly_expenses_value",
            "projected_net_burn_value",
            "projected_runway_months",
            "plan_adjusted_monthly_burn_value",
            "plan_adjusted_runway_months",
            "runway_window_days",
            "source_count",
            "account_count",
            "transaction_count_30d",
            "last_synced_at"
          ],
          "additionalProperties" => false
        },
        "sources" => %{
          "type" => "array",
          "items" => %{
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
              "provider" => %{"type" => ["string", "null"]},
              "config_key" => %{"type" => ["string", "null"]},
              "name" => %{"type" => ["string", "null"]},
              "external_id" => %{"type" => ["string", "null"]},
              "last_synced_at" => %{"type" => ["string", "null"]},
              "last_successful_sync_at" => %{"type" => ["string", "null"]},
              "last_error" => %{"type" => ["string", "null"]},
              "metadata" => %{"type" => ["object", "null"]}
            },
            "required" => [
              "id",
              "atlas_account",
              "provider",
              "config_key",
              "name",
              "external_id",
              "last_synced_at",
              "last_successful_sync_at",
              "last_error",
              "metadata"
            ],
            "additionalProperties" => false
          }
        },
        "source_count" => %{"type" => "integer"}
      },
      "required" => ["overview", "sources", "source_count"],
      "additionalProperties" => false
    }

  alias Atlas.Finance
  alias Atlas.Finance.Source
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Summarize treasury position in Atlas, including cash, 30-day net flow, smoothed burn, runway, account-based projections, and sync freshness."
  end

  def execute(conn, _args) do
    with :ok <- Tool.authorize_scope(conn, "finance:read", "Finance tools") do
      overview = Finance.overview()
      sources = Finance.list_sources() |> Enum.map(&serialize_source/1)

      {:ok,
       %{
         overview: serialize_overview(overview),
         sources: sources,
         source_count: length(sources)
       }}
    end
  end

  defp serialize_overview(overview) do
    %{
      currency: overview.currency,
      available_cash_value: decimal_to_string(overview.available_cash_value),
      total_balance_value: decimal_to_string(overview.total_balance_value),
      net_30d_value: decimal_to_string(overview.net_30d_value),
      monthly_burn_value: decimal_to_string(overview.monthly_burn_value),
      smoothed_monthly_burn_value: decimal_to_string(overview.smoothed_monthly_burn_value),
      runway_months: decimal_to_string(overview.runway_months),
      trailing_cash_runway_months: decimal_to_string(overview.trailing_cash_runway_months),
      smoothed_cash_runway_months: decimal_to_string(overview.smoothed_cash_runway_months),
      projected_monthly_revenue_value: decimal_to_string(overview.projected_monthly_revenue_value),
      projected_arr_value: decimal_to_string(overview.projected_arr_value),
      projected_customer_count: overview.projected_customer_count,
      projected_monthly_expenses_value: decimal_to_string(overview.projected_monthly_expenses_value),
      projected_net_burn_value: decimal_to_string(overview.projected_net_burn_value),
      projected_runway_months: decimal_to_string(overview.projected_runway_months),
      plan_adjusted_monthly_burn_value: decimal_to_string(overview.plan_adjusted_monthly_burn_value),
      plan_adjusted_runway_months: decimal_to_string(overview.plan_adjusted_runway_months),
      runway_window_days: overview.runway_window_days,
      source_count: overview.source_count,
      account_count: overview.account_count,
      transaction_count_30d: overview.transaction_count_30d,
      last_synced_at: Tool.iso8601(overview.last_synced_at)
    }
  end

  defp serialize_source(%Source{} = source) do
    %{
      id: source.id,
      atlas_account: serialize_atlas_account(source.atlas_account),
      provider: source.provider,
      config_key: source.config_key,
      name: source.name,
      external_id: source.external_id,
      last_synced_at: Tool.iso8601(source.last_synced_at),
      last_successful_sync_at: Tool.iso8601(source.last_successful_sync_at),
      last_error: source.last_error,
      metadata: source.metadata
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

  defp decimal_to_string(nil), do: nil
  defp decimal_to_string(value), do: Decimal.to_string(value)
end
