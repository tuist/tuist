defmodule TuistWeb.Noora.Pages.InlineDropdown do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Inline dropdown",
    description: "Opens a menu from a borderless text trigger that sits inline with surrounding content.",
    components: [{Noora.Dropdown, :inline_dropdown}, {Noora.Dropdown, :dropdown_item}],
    guidelines: [
      "Use an inline dropdown where a bordered trigger would be too heavy, such as a language switcher in a footer or a Manage menu in a card header. Use a dropdown for filters and sort controls.",
      "Show the current value as the `label`, and fill the menu with `dropdown_item`, the same items a dropdown takes.",
      "Small is the default size. Use `size=\"large\"` next to body text.",
      "The menu always closes when an item is selected. For multi-select menus, use a dropdown with `close_on_select` set to `false`.",
      "Use `patch`, `navigate`, or `href` on items that change the page, and `on_click` or `phx-click` on items that run an action."
    ]

  example "Default", description: "The label shows the current value." do
    ~H"""
    <.inline_dropdown id="inline-dropdown-default" label="English">
      <.dropdown_item value="en" label="English" />
      <.dropdown_item value="es" label="Español" />
      <.dropdown_item value="ja" label="日本語" />
      <.dropdown_item value="ko" label="한국어" />
      <.dropdown_item value="ru" label="Русский" />
    </.inline_dropdown>
    """
  end

  example "Sizes" do
    ~H"""
    <.inline_dropdown id="inline-dropdown-small" label="Small">
      <.dropdown_item value="small-option-a" label="Option A" />
      <.dropdown_item value="small-option-b" label="Option B" />
    </.inline_dropdown>
    <.inline_dropdown id="inline-dropdown-large" label="Large" size="large">
      <.dropdown_item value="large-option-a" label="Option A" />
      <.dropdown_item value="large-option-b" label="Option B" />
    </.inline_dropdown>
    """
  end

  example "With icon", description: "The `icon` slot adds an icon before the label." do
    ~H"""
    <.inline_dropdown id="inline-dropdown-icon" label="English" size="large">
      <:icon><.language /></:icon>
      <.dropdown_item value="en" label="English" />
      <.dropdown_item value="es" label="Español" />
      <.dropdown_item value="ja" label="日本語" />
    </.inline_dropdown>
    """
  end

  example "Actions", description: "A Manage menu for actions on the content it sits next to." do
    ~H"""
    <.inline_dropdown id="inline-dropdown-actions" label="Manage">
      <.dropdown_item value="settings" label="Connection settings">
        <:left_icon><.settings /></:left_icon>
      </.dropdown_item>
      <.dropdown_item value="remove" label="Remove connection">
        <:left_icon><.trash /></:left_icon>
      </.dropdown_item>
    </.inline_dropdown>
    """
  end

  example "Disabled" do
    ~H"""
    <.inline_dropdown id="inline-dropdown-disabled" label="Manage" disabled>
      <.dropdown_item value="remove" label="Remove connection" />
    </.inline_dropdown>
    """
  end
end
