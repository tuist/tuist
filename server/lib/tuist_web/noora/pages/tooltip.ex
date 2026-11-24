defmodule TuistWeb.Noora.Pages.Tooltip do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Tooltip",
    description: "Shows a short label or explanation when people hover over or focus an element.",
    components: [{Noora.Tooltip, :tooltip}],
    guidelines: [
      "Use a tooltip for supplementary information, such as the exact date behind a relative time or what a metric means. Never put the only way to understand or complete a task in a tooltip.",
      "Spread the attributes from the `:trigger` slot onto the element: `<:trigger :let={attrs}>` and then `{attrs}` on it. Use a focusable trigger, such as a button, or add `tabindex=\"0\"`, so keyboard users can open it.",
      "Give icon-only triggers an `aria-label` that says what the tooltip explains.",
      "Small tooltips show only the `title`. Use `size=\"large\"` with a `description` for a sentence or two of explanation, and the `:icon` slot to add an icon.",
      "Tooltips open after a short delay and stay open while the pointer moves onto them. On touch screens, a tap on the trigger toggles the tooltip.",
      "For content people need to click, such as a copy button, use a popover instead."
    ]

  example "Default", description: "A small tooltip shows its `title`." do
    ~H"""
    <.tooltip id="tooltip-default" title="Oct 20, 2026 at 14:32 UTC">
      <:trigger :let={attrs}>
        <span tabindex="0" {attrs}>3 hours ago</span>
      </:trigger>
    </.tooltip>
    """
  end

  example "Large", description: "A large tooltip adds a `description` and an optional icon." do
    ~H"""
    <.tooltip
      id="tooltip-large"
      size="large"
      title="Cache hit rate"
      description="The share of cacheable targets that were downloaded from the cache instead of built."
    >
      <:trigger :let={attrs}>
        <.button icon_only variant="secondary" size="small" aria-label="About cache hit rate" {attrs}>
          <.info_circle />
        </.button>
      </:trigger>
      <:icon><.database /></:icon>
    </.tooltip>
    """
  end

  example "Placement",
    description: "Tooltips open below the trigger, aligned to its start, by default. `placement` moves them." do
    ~H"""
    <.tooltip id="tooltip-placement-top" title="Opens above" placement="top">
      <:trigger :let={attrs}>
        <.button label="Top" variant="secondary" {attrs} />
      </:trigger>
    </.tooltip>
    <.tooltip id="tooltip-placement-bottom" title="Opens below, centered" placement="bottom">
      <:trigger :let={attrs}>
        <.button label="Bottom" variant="secondary" {attrs} />
      </:trigger>
    </.tooltip>
    <.tooltip id="tooltip-placement-bottom-start" title="Opens below, aligned to the start">
      <:trigger :let={attrs}>
        <.button label="Bottom start" variant="secondary" {attrs} />
      </:trigger>
    </.tooltip>
    """
  end

  example "On a badge", description: "Explains a status without taking up space in a table or header." do
    ~H"""
    <.tooltip
      id="tooltip-badge"
      size="large"
      title="Partial coverage"
      description="Some targets came from the binary cache without coverage counters, so their coverage is unknown."
    >
      <:trigger :let={attrs}>
        <span tabindex="0" {attrs}>
          <.badge label="Partial" color="warning" style="light-fill" />
        </span>
      </:trigger>
    </.tooltip>
    """
  end
end
