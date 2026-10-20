defmodule TuistWeb.Noora.Pages.Dropdown do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Dropdown",
    description: "Opens a menu of options or actions from a trigger button.",
    components: [{Noora.Dropdown, :dropdown}, {Noora.Dropdown, :dropdown_item}],
    guidelines: [
      "Keep `label` to the current value and use `secondary_text` for a prefix that names what the dropdown controls, such as `Sort by:` or `Environment:`.",
      "Use `patch` or `navigate` on items when the choice belongs in the URL, such as a sort order or a filter. Use `on_click` or `phx-click` for actions.",
      "Mark the current choice with a check in the item's `right_icon` slot.",
      "Separate groups of items with `<.dropdown_separator />`, for example to set destructive actions apart.",
      "For long lists, add a `:search` slot with an input that has `data-part=\"search-input\"`. The menu filters items by label and shows No results when nothing matches.",
      "Items with `checked` render a checkbox, and the LiveView owns its state. Set `close_on_select` to `false` so the menu stays open while people toggle options."
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
end
