defmodule Noora.BreadcrumbsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [sigil_H: 2]
  import Phoenix.LiveViewTest

  alias Noora.Breadcrumbs

  test "an image takes the place of the avatar" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Breadcrumbs.breadcrumb id="project" label="ios-app" image="/xcode.png" show_avatar />
      """)

    assert html =~ ~s(<img src="/xcode.png" alt="" width="20" height="20" data-part="image")
    refute html =~ ~s(data-part="avatar")
  end

  test "shows the avatar when there is no image" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Breadcrumbs.breadcrumb id="account" label="tuist" show_avatar />
      """)

    assert html =~ ~s(data-part="avatar")
    refute html =~ ~s(data-part="image")
  end

  test "a menu item shows its image instead of an icon or avatar" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Breadcrumbs.breadcrumb_item
        value="ios"
        label="ios-app"
        image="/xcode.png"
        icon="check"
        show_avatar
      />
      """)

    assert html =~ ~s(data-part="image")
    refute html =~ ~s(data-part="avatar")
    refute html =~ "icon-tabler-check"
  end

  test "a menu item is a Noora.Menu item, focusable by the breadcrumb's keyboard handling" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Breadcrumbs.breadcrumb_item id="ios" value="ios" label="ios-app" href="/tuist/ios-app" selected />
      """)

    assert html =~ ~s(class="noora-menu-item")
    assert html =~ ~s(href="/tuist/ios-app")
    assert html =~ ~s(role="menuitem")
    assert html =~ ~s(tabindex="-1")
    assert html =~ "data-selected"
    assert html =~ ~s(data-part="check")
    assert html =~ ~s(data-truncate="middle")
  end

  test "the menu is a Noora.Menu panel with the footer after a separator" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Breadcrumbs.breadcrumb id="project" label="ios-app">
        <Breadcrumbs.breadcrumb_item value="ios" label="ios-app" selected />
        <:footer>
          <Breadcrumbs.breadcrumb_item value="new" label="Create project" icon="plus" />
        </:footer>
      </Breadcrumbs.breadcrumb>
      """)

    assert html =~ ~s(class="noora-menu-panel" data-part="content")
    assert html =~ ~r/data-part="separator".*data-part="footer"/s
  end
end
