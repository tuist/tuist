defmodule TuistWeb.Noora.Pages.ButtonGroup do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Button group",
    description: "Joins related buttons into one control, typically to switch between views or options.",
    components: [{Noora.ButtonGroup, :button_group}, {Noora.ButtonGroup, :button_group_item}],
    guidelines: [
      "Use a button group for a small set of mutually exclusive options, such as Line and Scatter plot, or Grid and List view.",
      "The group does not track selection. Set `data-selected` on the active item from your own state, as the chart type toggle does.",
      "Pass `href`, `navigate`, or `patch` when each option is a separate page. The item then renders a link with the same appearance.",
      "Icon-only items need an `aria-label`, and an `aria-pressed` value when they act as toggles, as the theme switcher does.",
      "Keep labels to one or two words so the group stays compact."
    ]

  alias Phoenix.LiveView.JS

  example "Sizes", description: "Medium is the default." do
    ~H"""
    <.button_group size="small">
      <.button_group_item label="Builds" />
      <.button_group_item label="Tests" />
      <.button_group_item label="Cache" />
    </.button_group>
    <.button_group size="medium">
      <.button_group_item label="Builds" />
      <.button_group_item label="Tests" />
      <.button_group_item label="Cache" />
    </.button_group>
    <.button_group size="large">
      <.button_group_item label="Builds" />
      <.button_group_item label="Tests" />
      <.button_group_item label="Cache" />
    </.button_group>
    """
  end

  example "Selected item",
    description: "`data-selected` highlights the active option. Here it moves on click with `JS` commands." do
    ~H"""
    <.button_group id="button-group-chart-type">
      <.button_group_item
        label="Line"
        data-selected
        phx-click={
          JS.remove_attribute("data-selected", to: "#button-group-chart-type > [data-selected]")
          |> JS.set_attribute({"data-selected", "true"})
        }
      />
      <.button_group_item
        label="Scatter plot"
        phx-click={
          JS.remove_attribute("data-selected", to: "#button-group-chart-type > [data-selected]")
          |> JS.set_attribute({"data-selected", "true"})
        }
      />
    </.button_group>
    """
  end

  example "With icons", description: "Icons sit before or after the label." do
    ~H"""
    <.button_group>
      <.button_group_item label="Previous">
        <:icon_left><.chevron_left /></:icon_left>
      </.button_group_item>
      <.button_group_item label="Next">
        <:icon_right><.chevron_right /></:icon_right>
      </.button_group_item>
    </.button_group>
    """
  end

  example "Icon only", description: "For options whose icons are unambiguous. Every item needs an `aria-label`." do
    ~H"""
    <.button_group size="small">
      <.button_group_item icon_only data-selected aria-pressed="true" aria-label="System theme">
        <.device_desktop />
      </.button_group_item>
      <.button_group_item icon_only aria-pressed="false" aria-label="Light theme">
        <.sun_high />
      </.button_group_item>
      <.button_group_item icon_only aria-pressed="false" aria-label="Dark theme">
        <.moon />
      </.button_group_item>
    </.button_group>
    <.button_group>
      <.button_group_item icon_only data-selected aria-label="Grid view">
        <.layout_grid />
      </.button_group_item>
      <.button_group_item icon_only aria-label="List view">
        <.menu_2 />
      </.button_group_item>
    </.button_group>
    """
  end
end
