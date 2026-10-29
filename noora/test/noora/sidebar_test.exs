defmodule Noora.SidebarTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Noora.Sidebar

  test "persists sidebar scroll by its stable ID by default" do
    html = render_component(&Sidebar.sidebar/1, id: "navigation", inner_block: [])
    assert html =~ ~s(data-scroll-persist-key="navigation")
    assert html =~ ~s(phx-hook="NooraScrollArea")
  end

  test "allows scroll persistence to be disabled" do
    html = render_component(&Sidebar.sidebar/1, id: "navigation", persist_scroll: false, inner_block: [])
    refute html =~ "data-scroll-persist-key"
    assert html =~ ~s(phx-hook="NooraScrollArea")
  end
end
