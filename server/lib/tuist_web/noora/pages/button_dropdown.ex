defmodule TuistWeb.Noora.Pages.ButtonDropdown do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Button dropdown",
    description: "Pairs a main action with a menu of related alternatives behind an attached trigger.",
    components: [{Noora.ButtonDropdown, :button_dropdown}],
    guidelines: [
      "Make the main button the most common action, and keep the menu to variations of that same action, such as Copy page and View as Markdown.",
      "Build the menu from `dropdown_item`s in the inner block. Each item handles its own click through `on_click`, `href`, `navigate`, or `patch`.",
      "Extra attributes such as `phx-click` and `phx-hook` go to the main button, not to the trigger.",
      "Set `align=\"end\"` when the button sits at the right edge of its container, so the menu lines up with the button's right side.",
      "`disabled` disables both the main button and the trigger."
    ]

  example "Default", description: "The main button runs the action. The trigger opens the menu." do
    ~H"""
    <.button_dropdown id="button-dropdown-default" label="Copy page">
      <.dropdown_item value="copy-markdown" label="Copy page" on_click="copy-page-markdown" />
      <.dropdown_item value="view-markdown" label="View as Markdown" />
    </.button_dropdown>
    """
  end

  example "Sizes", description: "Large is the default, and medium is the only other size." do
    ~H"""
    <.button_dropdown id="button-dropdown-medium" label="Share preview" size="medium">
      <.dropdown_item value="copy-link" label="Copy link" />
      <.dropdown_item value="show-qr-code" label="Show QR code" />
    </.button_dropdown>
    <.button_dropdown id="button-dropdown-large" label="Share preview" size="large">
      <.dropdown_item value="copy-link" label="Copy link" />
      <.dropdown_item value="show-qr-code" label="Show QR code" />
    </.button_dropdown>
    """
  end

  example "With icons", description: "Icons in the button and in the items make the actions easier to scan." do
    ~H"""
    <.button_dropdown id="button-dropdown-icons" label="Copy page" size="medium">
      <:icon_left><.copy /></:icon_left>
      <.dropdown_item
        value="copy-markdown"
        label="Copy page"
        description="Copy page as Markdown for LLMs"
        size="large"
      >
        <:left_icon><.copy /></:left_icon>
      </.dropdown_item>
      <.dropdown_item
        value="view-markdown"
        label="View as Markdown"
        description="View this page as plain text"
        size="large"
      >
        <:left_icon><.markdown /></:left_icon>
        <:right_icon><.external_link /></:right_icon>
      </.dropdown_item>
    </.button_dropdown>
    """
  end

  example "Alignment", description: "`end` aligns the menu with the right edge of the button." do
    ~H"""
    <.button_dropdown id="button-dropdown-align-end" label="Download" size="medium" align="end">
      <:icon_left><.download /></:icon_left>
      <.dropdown_item value="ipa" label="Download .ipa" />
      <.dropdown_item value="app" label="Download .app" />
    </.button_dropdown>
    """
  end

  example "Disabled" do
    ~H"""
    <.button_dropdown id="button-dropdown-disabled" label="Retry build" disabled>
      <.dropdown_item value="retry-failed" label="Retry failed targets" />
      <.dropdown_item value="retry-all" label="Retry all targets" />
    </.button_dropdown>
    """
  end
end
