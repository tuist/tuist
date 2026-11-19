defmodule TuistWeb.Noora.Pages.TabMenu do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Tab menu",
    description: "Switches between views of the same content, in a horizontal row of tabs or a vertical list.",
    components: [
      {Noora.TabMenu, :tab_menu_horizontal},
      {Noora.TabMenu, :tab_menu_horizontal_item},
      {Noora.TabMenu, :tab_menu_vertical}
    ],
    guidelines: [
      "Use horizontal tabs for views of one resource, such as the overview, cache, and errors of a build. Use the sidebar for the sections of an app.",
      "Keep the selected tab in the URL. Pass `patch` with a query parameter, such as `?tab=overview`, and set `selected` from it.",
      "Horizontal items replace the current history entry by default, so the back button skips tab changes. Set `replace={false}` to keep each tab in the history.",
      "Without `patch`, `navigate`, or `href`, a horizontal item renders a plain element instead of a link.",
      "A vertical item is not a link. Wrap it in a `<.link>` that you style without an underline, and mark the current one with `data-selected`."
    ]

  example "Horizontal", description: "The selected tab is underlined.", layout: :column do
    ~H"""
    <.tab_menu_horizontal>
      <.tab_menu_horizontal_item label="Overview" patch="?tab=overview" selected />
      <.tab_menu_horizontal_item label="Cache" patch="?tab=cache" />
      <.tab_menu_horizontal_item label="Warnings" patch="?tab=warnings" />
      <.tab_menu_horizontal_item label="Errors" patch="?tab=errors" />
    </.tab_menu_horizontal>
    """
  end

  example "Horizontal with icons",
    description: "Icons go before the label with `icon_left`, or after it with `icon_right`.",
    layout: :column do
    ~H"""
    <.tab_menu_horizontal>
      <.tab_menu_horizontal_item label="General" patch="?tab=general" selected>
        <:icon_left><.settings /></:icon_left>
      </.tab_menu_horizontal_item>
      <.tab_menu_horizontal_item label="Members" patch="?tab=members">
        <:icon_left><.users /></:icon_left>
      </.tab_menu_horizontal_item>
      <.tab_menu_horizontal_item label="Integrations" patch="?tab=integrations">
        <:icon_left><.category /></:icon_left>
      </.tab_menu_horizontal_item>
    </.tab_menu_horizontal>
    """
  end

  example "Vertical", description: "Vertical items stack into a list of links.", layout: :column do
    ~H"""
    <nav aria-label="Guides" style="display: flex; flex-direction: column; max-width: 240px;">
      <.link style="text-decoration: none;" patch="?guide=quick-start">
        <.tab_menu_vertical label="Quick start" data-selected />
      </.link>
      <.link style="text-decoration: none;" patch="?guide=cache">
        <.tab_menu_vertical label="Cache" />
      </.link>
      <.link style="text-decoration: none;" patch="?guide=selective-testing">
        <.tab_menu_vertical label="Selective testing" />
      </.link>
      <.link style="text-decoration: none;" patch="?guide=previews">
        <.tab_menu_vertical label="Previews" />
      </.link>
    </nav>
    """
  end

  example "Vertical with icons",
    description: "The `icon_right` slot can mark links that leave the site.",
    layout: :column do
    ~H"""
    <nav aria-label="Resources" style="display: flex; flex-direction: column; max-width: 240px;">
      <.link style="text-decoration: none;" patch="?section=overview">
        <.tab_menu_vertical label="Overview" data-selected>
          <:icon_left><.smart_home /></:icon_left>
        </.tab_menu_vertical>
      </.link>
      <.link style="text-decoration: none;" patch="?section=cli">
        <.tab_menu_vertical label="CLI">
          <:icon_left><.devices_browser /></:icon_left>
        </.tab_menu_vertical>
      </.link>
      <.link
        style="text-decoration: none;"
        href="https://github.com/tuist/tuist"
        target="_blank"
        rel="noopener noreferrer"
      >
        <.tab_menu_vertical label="GitHub">
          <:icon_left><.brand_github /></:icon_left>
          <:icon_right><.external_link /></:icon_right>
        </.tab_menu_vertical>
      </.link>
    </nav>
    """
  end
end
