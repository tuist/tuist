defmodule Atlas.MCP.Tools.UpdateAccount do
  @moduledoc """
  Updates editable fields on an account. Tenancy-defining fields
  (account_key) and engine-owned fields (priority) are intentionally
  not exposed here.
  """

  use Atlas.MCP.Tool,
    name: "update_account",
    schema: %{
      "type" => "object",
      "description" => "Provide one of account_id, account_key, or handle plus the fields to change.",
      "properties" =>
        Map.merge(Atlas.MCP.AccountLookup.identifier_schema_properties(), %{
          "name" => %{"type" => "string"},
          "description" => %{"type" => "string"},
          "primary_domain" => %{"type" => "string"},
          "url" => %{"type" => "string"},
          "legal_name" => %{"type" => "string"},
          "contract_id" => %{"type" => "string"},
          "status" => %{"type" => "string", "enum" => ["active", "churned", "paused", "trial"]},
          "hosting" => %{
            "type" => "string",
            "enum" => Atlas.Accounts.Account.hosting_values(),
            "description" => "Cloud, self-hosted, or not yet recorded."
          },
          "churned_date" => %{"type" => "string", "format" => "date"},
          "churn_reason" => %{"type" => "string"},
          "segment" => %{"type" => "string", "enum" => ["customer", "lead", "prospect"]},
          "deal_stage" => %{"type" => "string"},
          "parent_account_id" => %{
            "type" => "string",
            "description" =>
              "UUID of another account to establish as this account's parent. Use an empty string to clear."
          },
          "currency" => %{"type" => "string"},
          "current_value" => %{"type" => "number"},
          "next_renewal_date" => %{"type" => "string", "format" => "date"},
          "stripe_customer_id" => %{"type" => "string"}
        })
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "account" => %{
          "type" => "object",
          "properties" => %{
            "id" => %{"type" => "string"},
            "account_key" => %{"type" => "string"},
            "name" => %{"type" => ["string", "null"]},
            "status" => %{"type" => ["string", "null"]},
            "segment" => %{"type" => ["string", "null"]},
            "hosting" => %{"type" => ["string", "null"]},
            "deal_stage" => %{"type" => ["string", "null"]},
            "parent_account_id" => %{"type" => ["string", "null"]},
            "currency" => %{"type" => ["string", "null"]},
            "current_value" => %{"type" => ["string", "null"]},
            "next_renewal_date" => %{"type" => ["string", "null"]}
          },
          "required" => [
            "id",
            "account_key",
            "name",
            "status",
            "segment",
            "hosting",
            "deal_stage",
            "parent_account_id",
            "currency",
            "current_value",
            "next_renewal_date"
          ],
          "additionalProperties" => false
        }
      },
      "required" => ["account"],
      "additionalProperties" => false
    }

  alias Atlas.Accounts
  alias Atlas.MCP.AccountLookup
  alias Atlas.MCP.Tool

  @editable_keys ~w(
    name description primary_domain url legal_name contract_id
    status churned_date churn_reason hosting segment deal_stage parent_account_id
    currency current_value next_renewal_date stripe_customer_id
  )

  @impl EMCP.Tool
  def description, do: "Update editable fields on an account."

  def execute(_conn, args) do
    with {:ok, account} <- AccountLookup.resolve(args) do
      attrs = Map.take(args, @editable_keys)

      case Accounts.update_account(account, attrs) do
        {:ok, updated} ->
          {:ok,
           %{
             account: %{
               id: updated.id,
               account_key: updated.account_key,
               name: updated.name,
               status: updated.status,
               segment: updated.segment,
               hosting: updated.hosting,
               deal_stage: updated.deal_stage,
               parent_account_id: updated.parent_account_id,
               currency: updated.currency,
               current_value: updated.current_value && Decimal.to_string(updated.current_value),
               next_renewal_date: Tool.iso8601(updated.next_renewal_date)
             }
           }}

        {:error, changeset} ->
          {:error, "Could not update account: #{Tool.format_changeset_errors(changeset)}"}
      end
    end
  end
end
