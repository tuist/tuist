defmodule Noora.TableTest do
  use ExUnit.Case, async: true
  use Phoenix.Component

  import Phoenix.LiveViewTest

  alias Noora.Table
  alias Phoenix.LiveView.JS

  test "disclosure remains client-side without a row toggle callback" do
    html = render_component(&expandable_table/1, %{toggle: nil, expanded: []})
    assert html =~ "toggle_attr"
    assert html =~ ~s(aria-expanded="false")
    assert html =~ ~s(aria-controls="row-expanded")
  end

  test "a row toggle callback delegates expansion and accessibility state to the server" do
    html =
      render_component(&expandable_table/1, %{
        toggle: fn row -> JS.push("load-details", value: %{key: row.id}) end,
        expanded: ["row"]
      })

    assert html =~ "load-details"
    refute html =~ "toggle_attr"
    assert html =~ ~s(data-state="expanded")
    assert html =~ ~s(aria-expanded="true")
  end

  defp expandable_table(assigns) do
    ~H"""
    <Table.table
      id="table"
      rows={[%{id: "row"}]}
      row_expandable={fn _ -> true end}
      row_toggle={@toggle}
      expanded_rows={@expanded}
    >
      <:col :let={row}>{row.id}</:col>
      <:expanded_content>Details</:expanded_content>
    </Table.table>
    """
  end
end
