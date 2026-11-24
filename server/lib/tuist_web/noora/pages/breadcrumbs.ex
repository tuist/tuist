defmodule TuistWeb.Noora.Pages.Breadcrumbs do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Breadcrumbs",
    description: "Shows where the current page sits in the hierarchy and lets people switch between its siblings.",
    components: [
      {Noora.Breadcrumbs, :breadcrumbs},
      {Noora.Breadcrumbs, :breadcrumb},
      {Noora.Breadcrumbs, :breadcrumb_item}
    ],
    guidelines: [
      "Order the trail from the broadest level to the current page, as the dashboard does: account, then project, then the page.",
      "Pass `href` to each `breadcrumb` so its label navigates. Nesting `breadcrumb_item`s adds a menu trigger next to the label for switching to a sibling.",
      "Mark the current entry in a menu with `selected`. It shows a check mark.",
      "Each breadcrumb shows one of an `image`, an avatar, or an icon. Use `show_avatar` for accounts and `image` for a project's build system logo. The image takes the place of the avatar and the icon.",
      "Put actions such as Create project in the `footer` slot. It stays below the scrollable list of items.",
      "Give every `breadcrumb` a unique `id`, and give a `breadcrumb_item` one when it shows an avatar, since the avatar's id is derived from it."
    ]

  example "Separators",
    description: "`slash` is the default. `arrow` suits paths such as files inside a bundle.",
    layout: :column do
    ~H"""
    <.breadcrumbs style="slash">
      <.breadcrumb id="breadcrumbs-slash-account" label="tuist" href="#separators" />
      <.breadcrumb id="breadcrumbs-slash-project" label="ios-app" href="#separators" />
      <.breadcrumb id="breadcrumbs-slash-page" label="Builds" href="#separators" />
    </.breadcrumbs>
    <.breadcrumbs style="arrow">
      <.breadcrumb id="breadcrumbs-arrow-bundle" label="Tuist.app" href="#separators" />
      <.breadcrumb id="breadcrumbs-arrow-frameworks" label="Frameworks" href="#separators" />
      <.breadcrumb id="breadcrumbs-arrow-framework" label="TuistKit.framework" href="#separators" />
    </.breadcrumbs>
    """
  end

  example "With menus",
    description: "Items nested in a breadcrumb open in a menu for switching between siblings.",
    layout: :column do
    ~H"""
    <.breadcrumbs>
      <.breadcrumb id="breadcrumbs-menu-account" label="tuist" href="#with-menus">
        <:icon><.smart_home /></:icon>
      </.breadcrumb>
      <.breadcrumb id="breadcrumbs-menu-project" label="ios-app" href="#with-menus">
        <.breadcrumb_item id="breadcrumbs-menu-ios-app" value="ios-app" label="ios-app" selected />
        <.breadcrumb_item id="breadcrumbs-menu-android-app" value="android-app" label="android-app" />
        <.breadcrumb_item id="breadcrumbs-menu-server" value="server" label="server" />
      </.breadcrumb>
      <.breadcrumb id="breadcrumbs-menu-page" label="Test runs" href="#with-menus" />
    </.breadcrumbs>
    """
  end

  example "Avatars and logos",
    description: "The dashboard header shows an avatar for each account and the build system's logo for each project.",
    layout: :column do
    ~H"""
    <.breadcrumbs>
      <.breadcrumb
        id="breadcrumbs-rich-account"
        label="tuist"
        href="#avatars-and-logos"
        show_avatar
        avatar_color="blue"
      >
        <.breadcrumb_item
          id="breadcrumbs-rich-account-tuist"
          value="tuist"
          label="tuist"
          show_avatar
          avatar_color="blue"
          selected
        />
        <.breadcrumb_item
          id="breadcrumbs-rich-account-rover"
          value="rover-labs"
          label="rover-labs"
          show_avatar
          avatar_color="orange"
        />
      </.breadcrumb>
      <.breadcrumb
        id="breadcrumbs-rich-project"
        label="ios-app"
        href="#avatars-and-logos"
        image="/images/build-systems/xcode.png"
      >
        <.breadcrumb_item
          id="breadcrumbs-rich-project-ios"
          value="ios-app"
          label="ios-app"
          image="/images/build-systems/xcode.png"
          selected
        />
        <.breadcrumb_item
          id="breadcrumbs-rich-project-android"
          value="android-app"
          label="android-app"
          image="/images/build-systems/gradle.png"
        />
        <.breadcrumb_item
          id="breadcrumbs-rich-project-server"
          value="server"
          label="server"
          image="/images/build-systems/mix.png"
        />
      </.breadcrumb>
      <.breadcrumb id="breadcrumbs-rich-page" label="Module cache" href="#avatars-and-logos" />
    </.breadcrumbs>
    """
  end

  example "Menu footer",
    description:
      "The `footer` slot holds actions that stay below the menu's list, such as creating a project. Open the ios-app menu to see it.",
    layout: :column do
    ~H"""
    <.breadcrumbs>
      <.breadcrumb
        id="breadcrumbs-footer-account"
        label="tuist"
        href="#menu-footer"
        show_avatar
        avatar_color="blue"
      />
      <.breadcrumb id="breadcrumbs-footer-project" label="ios-app" href="#menu-footer">
        <.breadcrumb_item id="breadcrumbs-footer-ios-app" value="ios-app" label="ios-app" selected />
        <.breadcrumb_item id="breadcrumbs-footer-watch-app" value="watch-app" label="watch-app" />
        <:footer>
          <.breadcrumb_item
            id="breadcrumbs-footer-create"
            value="create-project"
            label="Create project"
            icon="circle_plus"
          />
        </:footer>
      </.breadcrumb>
      <.breadcrumb id="breadcrumbs-footer-page" label="Previews" href="#menu-footer" />
    </.breadcrumbs>
    """
  end
end
