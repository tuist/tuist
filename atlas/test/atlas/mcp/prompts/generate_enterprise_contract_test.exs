defmodule Atlas.MCP.Prompts.GenerateEnterpriseContractTest do
  use Atlas.MCP.ToolCase

  alias Atlas.MCP.Prompts.GenerateEnterpriseContract

  describe "behaviour metadata" do
    test "name and description are stable" do
      assert GenerateEnterpriseContract.name() == "generate_enterprise_contract"
      assert is_binary(GenerateEnterpriseContract.description())
    end

    test "exposes account, output scope, contract id, and template set arguments" do
      args = GenerateEnterpriseContract.arguments()

      account_arg = Enum.find(args, &(&1.name == "account"))
      assert account_arg.required == true

      assert Enum.any?(args, &(&1.name == "contract_id"))
      assert Enum.any?(args, &(&1.name == "template_set"))
      assert Enum.any?(args, &(&1.name == "document_scope"))
    end
  end

  describe "template/2" do
    test "embeds the resolved account identity and references the contracts tools" do
      account = insert_account!(%{name: "Acme", account_key: "acme-contracts", legal_name: "Acme, Inc."})

      result =
        GenerateEnterpriseContract.template(nil, %{
          "account" => account.account_key,
          "contract_id" => "Acme-0626"
        })

      [%{role: "user", content: %{type: "text", text: text}}] = result.messages

      assert text =~ "Acme"
      assert text =~ "acme-contracts"
      assert text =~ "Acme, Inc."
      assert text =~ "Acme-0626"
      assert text =~ "2026-02"
      assert text =~ "list_contract_templates"
      assert text =~ "get_contract_template"
      assert text =~ "get_account"
      assert text =~ "Hosted vs Self-hosted"
      assert text =~ "MSA edits"
      assert text =~ "current request override pasted conversation context"
      assert text =~ "signed `download_url`"
    end

    test "falls back to a 'could not resolve' note when the account is unknown" do
      result =
        GenerateEnterpriseContract.template(nil, %{
          "account" => "no-such-account-#{System.unique_integer([:positive])}"
        })

      [%{content: %{text: text}}] = result.messages

      assert text =~ "Could not resolve"
      assert text =~ "TBD"
    end

    test "honors an explicit template_set" do
      account = insert_account!(%{name: "Beta", account_key: "beta-contracts"})

      result =
        GenerateEnterpriseContract.template(nil, %{
          "account" => account.account_key,
          "template_set" => "2026-02"
        })

      [%{content: %{text: text}}] = result.messages

      assert text =~ "template_set = `2026-02`"
    end

    test "limits a standalone order-form request to one order-form template" do
      account = insert_account!(%{name: "Whatnot", account_key: "whatnot"})

      result =
        GenerateEnterpriseContract.template(nil, %{
          "account" => account.account_key,
          "contract_id" => "Whatnot-0626",
          "document_scope" => "order_form"
        })

      assert result.description == "Workflow for preparing a standalone order form."
      [%{content: %{text: text}}] = result.messages

      assert text =~ "standalone order form"
      assert text =~ "exactly one order-form template"
      assert text =~ "One filled Word order form"
      assert text =~ "instead of blocking on this value"
      refute text =~ "`msa.docx`"
      refute text =~ "`annex-2-dpa.docx`"
      refute text =~ "curl"
    end
  end
end
