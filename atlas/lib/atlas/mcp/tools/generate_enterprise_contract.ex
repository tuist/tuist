defmodule Atlas.MCP.Tools.GenerateEnterpriseContract do
  @moduledoc """
  Exposes the enterprise-contract prompt workflow as a tool so hosted clients
  that only load tools can discover and invoke it from natural-language
  contract and order-form requests.
  """

  use Atlas.MCP.Tool,
    name: "generate_enterprise_contract",
    schema: %{
      "type" => "object",
      "description" =>
        "Starts the official Atlas workflow for a standalone order form or a complete enterprise-contract package.",
      "required" => ["account"],
      "properties" => %{
        "account" => %{
          "type" => "string",
          "description" => "Account handle, account_key, or UUID to contract with."
        },
        "document_scope" => %{
          "type" => "string",
          "enum" => ["order_form", "contract_package"],
          "description" =>
            "Use order_form for one standalone order form or contract_package for the Master Services Agreement, annexes, and one order form. Defaults to contract_package."
        },
        "contract_id" => %{
          "type" => "string",
          "description" => "Optional contract identifier used for output naming, for example Acme-0426."
        },
        "template_set" => %{
          "type" => "string",
          "description" => "Optional template set. Defaults to the current Atlas template set."
        }
      }
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "document_scope" => %{"type" => "string", "enum" => ["order_form", "contract_package"]},
        "workflow" => %{"type" => "string"},
        "next_tools" => %{"type" => "array", "items" => %{"type" => "string"}}
      },
      "required" => ["document_scope", "workflow", "next_tools"],
      "additionalProperties" => false
    }

  alias Atlas.MCP.Prompts.GenerateEnterpriseContract, as: ContractPrompt
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Use this whenever the user asks to generate or prepare an enterprise contract, contract package, Master Services Agreement, or order form. Returns the official Atlas workflow that retrieves customer data and attaches the correct Word templates."
  end

  def execute(conn, args) do
    with :ok <- Tool.authorize_scope(conn, "contracts:write", "Enterprise contracts"),
         {:ok, account} <- fetch_account(args) do
      args = Map.put(args, "account", account)
      result = ContractPrompt.template(conn, args)
      [%{content: %{text: workflow}}] = result.messages

      {:ok,
       %{
         document_scope: document_scope(args),
         workflow: workflow,
         next_tools: ["get_account", "list_contract_templates", "get_contract_template"]
       }}
    end
  end

  defp fetch_account(%{"account" => account}) when is_binary(account) and account != "", do: {:ok, account}

  defp fetch_account(_args), do: {:error, "account is required."}

  defp document_scope(%{"document_scope" => "order_form"}), do: "order_form"
  defp document_scope(_args), do: "contract_package"
end
