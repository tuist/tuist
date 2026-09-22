defmodule Atlas.MCP.Tools.CreateAccount do
  @moduledoc """
  Creates a manually managed account.
  """

  use Atlas.MCP.Tool,
    name: "create_account",
    schema: %{
      "type" => "object",
      "required" => ["name"],
      "properties" => %{
        "name" => %{"type" => "string"},
        "description" => %{"type" => "string"},
        "primary_domain" => %{"type" => "string"},
        "url" => %{"type" => "string"},
        "legal_name" => %{"type" => "string"},
        "contract_id" => %{"type" => "string"},
        "status" => %{"type" => "string", "enum" => Atlas.Accounts.Account.statuses()},
        "hosting" => %{
          "type" => "string",
          "enum" => Atlas.Accounts.Account.hosting_values(),
          "description" => "Cloud, self-hosted, or not yet recorded."
        },
        "segment" => %{
          "type" => "string",
          "enum" => Enum.map(Atlas.Accounts.Account.segments(), &Atom.to_string/1),
          "description" => "Defaults to prospect when omitted."
        },
        "deal_stage" => %{
          "type" => "string",
          "enum" => Atlas.Accounts.DealStage.keys(),
          "description" => "Current sales stage."
        },
        "parent_account_id" => %{"type" => "string"},
        "currency" => %{"type" => "string"},
        "current_value" => %{"type" => "number"},
        "next_renewal_date" => %{"type" => "string", "format" => "date"},
        "poc_end_date" => %{"type" => "string", "format" => "date"},
        "stripe_customer_id" => %{"type" => "string"}
      }
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "account" => Atlas.MCP.Serializers.Accounts.account_schema(),
        "account_url" => %{"type" => "string"}
      },
      "required" => ["account", "account_url"],
      "additionalProperties" => false
    }

  alias Atlas.Accounts
  alias Atlas.MCP.Serializers.Accounts, as: AccountSerializer
  alias Atlas.MCP.Tool

  @manual_keys ~w(
    name description primary_domain url legal_name contract_id status hosting segment
    deal_stage parent_account_id currency current_value next_renewal_date
    poc_end_date stripe_customer_id
  )

  @impl EMCP.Tool
  def description, do: "Create a manually managed account."

  def execute(_conn, args) do
    attrs = Map.take(args, @manual_keys)

    case Accounts.create_manual_account(attrs) do
      {:ok, account} ->
        account = Accounts.get_account(account.id)

        {:ok,
         %{
           account: AccountSerializer.account(account),
           account_url: Tool.account_url(account.id)
         }}

      {:error, changeset} ->
        {:error, "Could not create account: #{Tool.format_changeset_errors(changeset)}"}
    end
  end
end
