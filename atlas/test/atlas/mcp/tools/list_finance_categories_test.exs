defmodule Atlas.MCP.Tools.ListFinanceCategoriesTest do
  use Atlas.MCP.ToolCase

  import Atlas.FinanceFixtures

  alias Atlas.MCP.Tools.ListFinanceCategories

  test "lists finance categories for executives" do
    conn = executive_mcp_conn()

    software = insert_finance_category!(%{name: "Software", direction: "debit"})
    _revenue = insert_finance_category!(%{name: "Revenue", direction: "credit"})

    {:ok, payload} = execute_tool(ListFinanceCategories, conn, %{"direction" => "debit"})

    assert payload.count == 1
    software_slug = software.slug

    assert [
             %{
               name: "Software",
               slug: ^software_slug,
               direction: "debit"
             }
           ] = payload.categories
  end

  test "rejects non-executive users" do
    conn =
      %{role: :employee}
      |> insert_user!()
      |> mcp_conn()

    assert {:error, "Finance tools are only available to executives."} =
             execute_tool(ListFinanceCategories, conn, %{})
  end
end
