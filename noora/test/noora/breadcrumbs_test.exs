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
end
