defmodule TuistWeb.Noora.Pages.Dropdown do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Dropdown",
    description:
      "Opens a menu of options or actions from a trigger button. The inline dropdown uses a borderless text trigger, and the button dropdown pairs a main action with a menu of alternatives.",
    components: [
      {Noora.Dropdown, :dropdown},
      {Noora.Dropdown, :dropdown_item},
      {Noora.Dropdown, :inline_dropdown},
      {Noora.ButtonDropdown, :button_dropdown}
    ],
    guidelines: [
      "Keep `label` to the current value and use `secondary_text` for a prefix that names what the dropdown controls, such as `Sort by:` or `Environment:`.",
      "Use `patch` or `navigate` on items when the choice belongs in the URL, such as a sort order or a filter. Use `on_click` or `phx-click` for actions.",
      "Mark the current choice with a check in the item's `right_icon` slot.",
      "Separate groups of items with `<.dropdown_separator />`, for example to set destructive actions apart.",
      "For long lists, add a `:search` slot with an input that has `data-part=\"search-input\"`. The menu filters items by label and shows No results when nothing matches.",
      "Items with `checked` render a checkbox, and the LiveView owns its state. Set `close_on_select` to `false` so the menu stays open while people toggle options.",
      "Use an inline dropdown where a bordered trigger would be too heavy, such as a language switcher in a footer or a Manage menu in a card header. Its menu always closes when an item is selected.",
      "In a button dropdown, make the main button the most common action and keep the menu to variations of it, such as Copy page and View as Markdown. Extra attributes such as `phx-click` go to the main button, and `disabled` disables both parts.",
      "Set `align=\"end\"` on a button dropdown at the right edge of its container, so the menu lines up with the button's right side."
    ]

  example "Default", description: "A label, an optional `secondary_text` prefix, and the items to choose from." do
    ~H"""
    <.dropdown id="dropdown-default" label="CI" secondary_text="Environment:">
      <.dropdown_item value="any" label="Any" />
      <.dropdown_item value="ci" label="CI">
        <:right_icon><.check /></:right_icon>
      </.dropdown_item>
      <.dropdown_item value="local" label="Local" />
    </.dropdown>
    """
  end

  example "Sizes", description: "Large is the default. Use medium in dense toolbars." do
    ~H"""
    <.dropdown id="dropdown-size-large" label="Ran at" secondary_text="Sort by:">
      <.dropdown_item value="ran-at" label="Ran at" />
      <.dropdown_item value="duration" label="Duration" />
      <.dropdown_item value="hit-rate" label="Hit rate" />
    </.dropdown>
    <.dropdown id="dropdown-size-medium" label="Ran at" secondary_text="Sort by:" size="medium">
      <.dropdown_item value="ran-at" label="Ran at" />
      <.dropdown_item value="duration" label="Duration" />
      <.dropdown_item value="hit-rate" label="Hit rate" />
    </.dropdown>
    """
  end

  example "With icons",
    description: "The `icon` slot adds an icon to the trigger. Items take `left_icon` and `right_icon`." do
    ~H"""
    <.dropdown id="dropdown-icons" label="Last 30 days">
      <:icon><.calendar_week /></:icon>
      <.dropdown_item value="last-7-days" label="Last 7 days">
        <:left_icon><.clock_hour_4 /></:left_icon>
      </.dropdown_item>
      <.dropdown_item value="last-30-days" label="Last 30 days">
        <:left_icon><.clock_hour_4 /></:left_icon>
        <:right_icon><.check /></:right_icon>
      </.dropdown_item>
      <.dropdown_item value="last-12-months" label="Last 12 months">
        <:left_icon><.clock_hour_4 /></:left_icon>
      </.dropdown_item>
    </.dropdown>
    """
  end

  example "Icon only", description: "A compact trigger for row actions in tables and cards." do
    ~H"""
    <.dropdown id="dropdown-icon-only" icon_only>
      <:icon><.dots_vertical /></:icon>
      <.dropdown_item value="edit" label="Edit endpoint">
        <:left_icon><.pencil /></:left_icon>
      </.dropdown_item>
      <.dropdown_item value="rotate" label="Rotate secret">
        <:left_icon><.reload /></:left_icon>
      </.dropdown_item>
      <.dropdown_separator />
      <.dropdown_item value="delete" label="Delete endpoint">
        <:left_icon><.trash /></:left_icon>
      </.dropdown_item>
    </.dropdown>
    """
  end

  example "Large items", description: "Large items show a `description` under the label." do
    ~H"""
    <.dropdown id="dropdown-large-items" label="Admin">
      <.dropdown_item
        value="user"
        label="User"
        size="large"
        description="Can view projects, builds, and test runs."
      >
        <:left_icon><.user /></:left_icon>
      </.dropdown_item>
      <.dropdown_item
        value="admin"
        label="Admin"
        size="large"
        description="Can also manage members, billing, and tokens."
      >
        <:left_icon><.users /></:left_icon>
      </.dropdown_item>
    </.dropdown>
    """
  end

  example "Search", description: "A search input at the top of the menu filters long lists." do
    ~H"""
    <.dropdown id="dropdown-search" label="All schemes" secondary_text="Scheme:">
      <:search>
        <input type="text" placeholder="Search..." data-part="search-input" />
      </:search>
      <.dropdown_item value="all" label="All schemes" />
      <.dropdown_item value="App" label="App" />
      <.dropdown_item value="AppTests" label="AppTests" />
      <.dropdown_item value="AppUITests" label="AppUITests" />
      <.dropdown_item value="Core" label="Core" />
      <.dropdown_item value="CoreTests" label="CoreTests" />
      <.dropdown_item value="Networking" label="Networking" />
      <.dropdown_item value="NetworkingTests" label="NetworkingTests" />
    </.dropdown>
    """
  end

  example "Checkboxes", description: "Items with `checked` render a checkbox for choosing several options." do
    ~H"""
    <.dropdown id="dropdown-checkboxes" label="Mon, Wed, Fri" close_on_select={false}>
      <.dropdown_item value="monday" label="Monday" checked={true} />
      <.dropdown_item value="tuesday" label="Tuesday" checked={false} />
      <.dropdown_item value="wednesday" label="Wednesday" checked={true} />
      <.dropdown_item value="thursday" label="Thursday" checked={false} />
      <.dropdown_item value="friday" label="Friday" checked={true} />
    </.dropdown>
    """
  end

  example "Inline dropdown", description: "The label shows the current value." do
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

  example "Inline dropdown with icon", description: "The `icon` slot adds an icon before the label." do
    ~H"""
    <.inline_dropdown id="inline-dropdown-icon" label="English">
      <:icon><.language /></:icon>
      <.dropdown_item value="en" label="English" />
      <.dropdown_item value="es" label="Español" />
      <.dropdown_item value="ja" label="日本語" />
    </.inline_dropdown>
    """
  end

  example "Inline dropdown actions", description: "A Manage menu for actions on the content it sits next to." do
    ~H"""
    <.inline_dropdown id="inline-dropdown-actions-example" label="Manage">
      <.dropdown_item value="settings" label="Connection settings">
        <:left_icon><.settings /></:left_icon>
      </.dropdown_item>
      <.dropdown_item value="remove" label="Remove connection">
        <:left_icon><.trash /></:left_icon>
      </.dropdown_item>
    </.inline_dropdown>
    """
  end

  example "Inline dropdown disabled" do
    ~H"""
    <.inline_dropdown id="inline-dropdown-disabled-example" label="Manage" disabled>
      <.dropdown_item value="remove" label="Remove connection" />
    </.inline_dropdown>
    """
  end

  example "Button dropdown", description: "The main button runs the action. The trigger opens the menu." do
    ~H"""
    <.button_dropdown id="button-dropdown-default" label="Copy page">
      <.dropdown_item value="copy-markdown" label="Copy page" on_click="copy-page-markdown" />
      <.dropdown_item value="view-markdown" label="View as Markdown" />
    </.button_dropdown>
    """
  end

  example "Button dropdown sizes", description: "Large is the default, and medium is the only other size." do
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

  example "Button dropdown with icons",
    description: "Icons in the button and in the items make the actions easier to scan." do
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

  example "Button dropdown alignment", description: "`end` aligns the menu with the right edge of the button." do
    ~H"""
    <.button_dropdown id="button-dropdown-align-end" label="Download" size="medium" align="end">
      <:icon_left><.download /></:icon_left>
      <.dropdown_item value="ipa" label="Download .ipa" />
      <.dropdown_item value="app" label="Download .app" />
    </.button_dropdown>
    """
  end

  example "Button dropdown disabled" do
    ~H"""
    <.button_dropdown id="button-dropdown-disabled-example" label="Retry build" disabled>
      <.dropdown_item value="retry-failed" label="Retry failed targets" />
      <.dropdown_item value="retry-all" label="Retry all targets" />
    </.button_dropdown>
    """
  end
end
