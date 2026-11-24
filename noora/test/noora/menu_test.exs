defmodule Noora.MenuTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [sigil_H: 2]
  import Phoenix.LiveViewTest

  alias Noora.Menu

  test "renders a labelled button and the items into the menu hook" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Menu.menu id="actions" label="Actions" on_select="act">
        <Menu.menu_item value="rename" label="Rename" />
      </Menu.menu>
      """)

    assert html =~ ~s(phx-hook="NooraMenu")
    assert html =~ ~s(data-trigger="dropdown")
    assert html =~ ~s(data-on-select="act")
    assert html =~ ~s(data-positioning-placement="bottom-start")
    assert html =~ ~s(data-positioning-offset-main-axis="8")
    assert html =~ ~s(<span data-part="label"><span class="noora-middle-truncate">)
    assert html =~ ~s(data-part="indicator")
    assert html =~ ~s(data-value="rename")
  end

  test "renders a dots button named by its label for screen readers" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Menu.menu id="more" label="More actions" trigger="dots">
        <Menu.menu_item value="rename" label="Rename" />
      </Menu.menu>
      """)

    assert html =~ "data-icon-only"
    assert html =~ ~s(aria-label="More actions")
    assert html =~ "icon-tabler-dots-vertical"
    refute html =~ ~s(title="More actions")
    refute html =~ ~s(data-part="indicator")
  end

  test "renders a split button whose label runs the action and whose chevron opens the menu" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Menu.menu id="copy" label="Copy page" trigger="split" on_action="copy_page">
        <Menu.menu_item value="markdown" label="Copy as Markdown" />
      </Menu.menu>
      """)

    assert html =~ ~s(data-trigger="split")
    assert html =~ ~s(data-positioning-anchor="root")
    assert html =~ ~r/data-part="main-button"[^>]*phx-click="copy_page"/
    assert html =~ ~s(aria-label="Copy page options")
    assert html =~ ~s(id="copy-trigger-target")
  end

  test "disables the trigger of a menu without items, but not a split button's action" do
    assigns = %{items: []}

    label =
      rendered_to_string(~H"""
      <Menu.menu id="branches" label="Branch">
        <Menu.menu_item :for={item <- @items} value={item} label={item} />
      </Menu.menu>
      """)

    split =
      rendered_to_string(~H"""
      <Menu.menu id="copy" label="Copy page" trigger="split" on_action="copy_page">
        <Menu.menu_item :for={item <- @items} value={item} label={item} />
      </Menu.menu>
      """)

    assert label =~ "data-empty"
    assert label =~ ~r/data-part="trigger"[^>]*disabled/
    assert split =~ ~r/data-part="trigger"[^>]*disabled/
    refute split =~ ~r/data-part="main-button"[^>]*disabled/
  end

  test "treats a menu whose items render only comments as empty" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Menu.menu id="branches" label="Branch">
        <!-- no branches yet -->
      </Menu.menu>
      """)

    assert html =~ "data-empty"
  end

  test "keeps the trigger of a menu with items enabled" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Menu.menu id="actions" label="Actions">
        <Menu.menu_item value="rename" label="Rename" />
      </Menu.menu>
      """)

    refute html =~ "data-empty"
    refute html =~ ~r/data-part="trigger"[^>]*disabled/
  end

  test "renders an item's sublabel, description, icon, image, and extra content" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Menu.menu_item value="ios" label="ios-app" sublabel="Xcode" description="The iOS app">
        <:image><img src="/xcode.png" alt="" /></:image>
        <:icon><svg /></:icon>
        <:extra><kbd>⌘K</kbd></:extra>
      </Menu.menu_item>
      """)

    assert html =~ ~s(<span data-part="sublabel">(Xcode\)</span>)
    assert html =~ ~s(<span data-part="description">The iOS app</span>)
    assert html =~ ~s(data-part="image")
    assert html =~ ~s(data-part="icon")
    assert html =~ ~s(<kbd>⌘K</kbd>)
  end

  test "renders links as anchors, and disabled links as inert items" do
    assigns = %{}

    link = rendered_to_string(~H|<Menu.menu_item value="docs" label="Docs" href="/docs" />|)
    disabled = rendered_to_string(~H|<Menu.menu_item value="docs" label="Docs" href="/docs" disabled />|)

    assert link =~ ~s(<a href="/docs")
    refute disabled =~ "href="
    assert disabled =~ "data-disabled"
  end

  test "middle-truncates identifiers and gives long end-truncated labels a title" do
    assigns = %{}

    middle =
      rendered_to_string(
        ~H|<Menu.menu_item value="s" label="TuistAcceptanceTests-iOS-Simulator-Release" truncate="middle" />|
      )

    short = rendered_to_string(~H|<Menu.menu_item value="r" label="Rename project" />|)

    long =
      rendered_to_string(~H|<Menu.menu_item value="r" label="Rename the northwind-ios-app project" />|)

    assert middle =~ ~s(data-truncate="middle")
    assert middle =~ ~s(<span data-part="tail">-Release</span>)
    assert short =~ ~s(<span data-part="label">Rename project</span>)
    assert long =~ ~s(title="Rename the northwind-ios-app project")
  end

  test "renders checkbox items with their state, beside an icon" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Menu.menu_item value="branch" label="Branch" checked>
        <:icon><svg /></:icon>
      </Menu.menu_item>
      """)

    plain = rendered_to_string(~H|<Menu.menu_item value="rename" label="Rename" />|)

    assert html =~ "data-checkbox"
    assert html =~ ~s(data-checked="true")
    assert html =~ ~r/<div data-part="checkbox">\s*<div class="noora-checkbox-control" data-state="checked">/
    assert html =~ ~s(data-part="icon")
    refute plain =~ "data-checkbox"
  end

  test "marks destructive and selected items" do
    assigns = %{}

    destructive = rendered_to_string(~H|<Menu.menu_item value="delete" label="Delete" variant="destructive" />|)
    selected = rendered_to_string(~H|<Menu.menu_item value="all" label="All" selected />|)

    assert destructive =~ ~s(data-variant="destructive")
    assert selected =~ ~s(data-part="check")
    refute destructive =~ ~s(data-part="check")
  end
end
