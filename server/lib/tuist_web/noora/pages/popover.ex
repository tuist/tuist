defmodule TuistWeb.Noora.Pages.Popover do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Popover",
    description: "Shows interactive content, such as details or a short form, next to the element that opened it.",
    components: [{Noora.Popover, :popover}],
    guidelines: [
      "Use a popover for content people interact with: copying a value, editing a filter, or reading details. For a short label on hover, use a tooltip.",
      "Spread the attributes from the `:trigger` slot onto a focusable element, such as a button: `<:trigger :let={attrs}>` and then `{attrs}` on it.",
      "The popover's content has no padding of its own, so add spacing to what you put inside it.",
      "Close a popover from your own controls with `JS.dispatch(\"phx:close-popover\", detail: %{id: id})`, or open one from anywhere with `phx:open-popover`. Escape and a click outside also close it unless you turn them off.",
      "Set `modal` to trap focus inside the popover and block interaction with the rest of the page while it is open."
    ]

  alias Phoenix.LiveView.JS

  example "Default", description: "Click the trigger to open the popover. Escape or a click outside closes it." do
    ~H"""
    <.popover id="popover-default">
      <:trigger :let={attrs}>
        <.button label="Cache key" variant="secondary" {attrs} />
      </:trigger>
      <div style="display: flex; flex-direction: column; gap: var(--noora-spacing-4); padding: var(--noora-spacing-6); max-width: 320px;">
        <span style="font: var(--noora-font-weight-medium) var(--noora-font-body-medium);">Cache key</span>
        <code style="overflow-wrap: anywhere;">0f3a9c27e1b84d5c96a2f7e0b13d48c5a7e2f9d1</code>
      </div>
    </.popover>
    """
  end

  example "Placement",
    description: "The popover opens below the trigger by default. It also opens above it, aligned to either edge." do
    ~H"""
    <.popover id="popover-top" placement="top">
      <:trigger :let={attrs}>
        <.button label="Top" variant="secondary" {attrs} />
      </:trigger>
      <p style="margin: 0; padding: var(--noora-spacing-5) var(--noora-spacing-6);">
        Opens above the trigger.
      </p>
    </.popover>
    <.popover id="popover-bottom-start" placement="bottom-start">
      <:trigger :let={attrs}>
        <.button label="Bottom start" variant="secondary" {attrs} />
      </:trigger>
      <p style="margin: 0; padding: var(--noora-spacing-5) var(--noora-spacing-6);">
        Aligned to the trigger's start edge.
      </p>
    </.popover>
    <.popover id="popover-bottom-end" placement="bottom-end">
      <:trigger :let={attrs}>
        <.button label="Bottom end" variant="secondary" {attrs} />
      </:trigger>
      <p style="margin: 0; padding: var(--noora-spacing-5) var(--noora-spacing-6);">
        Aligned to the trigger's end edge.
      </p>
    </.popover>
    """
  end

  example "With a form", description: "Forms in a popover close it from their own Cancel button." do
    ~H"""
    <.popover id="popover-form" placement="bottom-start">
      <:trigger :let={attrs}>
        <.button label="Rename project" variant="secondary" {attrs} />
      </:trigger>
      <form
        phx-submit="rename_project"
        style="display: flex; flex-direction: column; gap: var(--noora-spacing-5); padding: var(--noora-spacing-6); width: 280px;"
      >
        <.text_input id="popover-form-name" name="name" value="ios-app" label="Project name" />
        <div style="display: flex; justify-content: flex-end; gap: var(--noora-spacing-4);">
          <.button
            type="button"
            label="Cancel"
            variant="secondary"
            size="medium"
            phx-click={JS.dispatch("phx:close-popover", detail: %{id: "popover-form"})}
          />
          <.button type="submit" label="Save" size="medium" />
        </div>
      </form>
    </.popover>
    """
  end

  example "Modal",
    description: "With `modal`, focus stays inside the popover and the rest of the page is blocked while it is open." do
    ~H"""
    <.popover id="popover-modal" modal>
      <:trigger :let={attrs}>
        <.button label="Edit description" variant="secondary" {attrs} />
      </:trigger>
      <div style="display: flex; flex-direction: column; gap: var(--noora-spacing-5); padding: var(--noora-spacing-6); width: 280px;">
        <.text_input
          id="popover-modal-description"
          name="description"
          value="The Tuist iOS app"
          label="Description"
        />
        <.button
          type="button"
          label="Done"
          size="medium"
          phx-click={JS.dispatch("phx:close-popover", detail: %{id: "popover-modal"})}
        />
      </div>
    </.popover>
    """
  end
end
