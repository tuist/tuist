defmodule Atlas.MCP.Tools.ListContractTemplatesTest do
  use Atlas.MCP.ToolCase

  alias Atlas.MCP.Tools.ListContractTemplates

  test "positions template listing after the contract-generation workflow" do
    description = ListContractTemplates.description()

    assert description =~ "after generate_enterprise_contract"
    assert description =~ "never draft a substitute from scratch"
  end

  test "returns the current template set and its templates for an executive" do
    conn = executive_mcp_conn()

    {:ok, payload} = execute_tool(ListContractTemplates, conn, %{})

    assert payload.template_set == "2026-02"
    assert "2026-02" in payload.available_template_sets

    filenames = payload.templates |> Enum.map(& &1.filename) |> Enum.sort()

    assert "msa.docx" in filenames
    assert "annex-2-dpa.docx" in filenames
    assert "order-form-tuist-hosted.docx" in filenames
  end

  test "honors an explicit template_set argument" do
    conn = executive_mcp_conn()

    {:ok, payload} = execute_tool(ListContractTemplates, conn, %{"template_set" => "2026-02"})

    assert payload.template_set == "2026-02"
    refute payload.templates == []
  end

  test "refuses non-executive users" do
    user = insert_user!(%{role: :employee})

    assert {:error, message} = execute_tool(ListContractTemplates, mcp_conn(user), %{})
    assert message =~ "Contract templates"
  end

  test "refuses unauthenticated requests" do
    assert {:error, message} = execute_tool(ListContractTemplates, %{assigns: %{}}, %{})
    assert message =~ "Contract templates"
  end
end
