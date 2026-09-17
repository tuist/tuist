defmodule Atlas.MCP.Tools.GenerateEnterpriseContractTest do
  use Atlas.MCP.ToolCase

  alias Atlas.MCP.Tools.GenerateEnterpriseContract

  describe "metadata" do
    test "advertises the contract-generation intent and document scopes" do
      assert GenerateEnterpriseContract.name() == "generate_enterprise_contract"
      assert GenerateEnterpriseContract.description() =~ "order form"

      schema = GenerateEnterpriseContract.input_schema()

      assert schema["required"] == ["account"]
      assert schema["properties"]["document_scope"]["enum"] == ["order_form", "contract_package"]
    end
  end

  describe "execute/2" do
    test "returns the standalone order-form workflow" do
      account = insert_account!(%{name: "Whatnot", account_key: "whatnot"})

      assert {:ok, payload} =
               execute_tool(GenerateEnterpriseContract, executive_mcp_conn(), %{
                 "account" => account.account_key,
                 "contract_id" => "Whatnot-0626",
                 "document_scope" => "order_form"
               })

      assert payload.document_scope == "order_form"
      assert payload.next_tools == ["get_account", "list_contract_templates", "get_contract_template"]
      assert payload.workflow =~ "standalone order form"
      assert payload.workflow =~ "embedded resource"
      assert payload.workflow =~ "exactly one order-form template"
      assert payload.workflow =~ "instead of blocking on this value"
      refute payload.workflow =~ "`msa.docx`"
      refute payload.workflow =~ "`annex-2-dpa.docx`"
    end

    test "defaults to the complete contract-package workflow" do
      account = insert_account!(%{name: "Acme", account_key: "acme"})

      assert {:ok, payload} =
               execute_tool(GenerateEnterpriseContract, executive_mcp_conn(), %{
                 "account" => account.account_key
               })

      assert payload.document_scope == "contract_package"
      assert payload.workflow =~ "`msa.docx`"
      assert payload.workflow =~ "`annex-2-dpa.docx`"
      assert payload.workflow =~ "`order-form-tuist-hosted.docx`"
    end

    test "requires an account" do
      assert {:error, "account is required."} =
               execute_tool(GenerateEnterpriseContract, executive_mcp_conn(), %{})
    end

    test "refuses non-executive users" do
      user = insert_user!(%{role: :employee})

      assert {:error, message} =
               execute_tool(GenerateEnterpriseContract, mcp_conn(user), %{"account" => "whatnot"})

      assert message =~ "Enterprise contracts"
    end
  end
end
