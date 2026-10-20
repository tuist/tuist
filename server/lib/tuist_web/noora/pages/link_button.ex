defmodule TuistWeb.Noora.Pages.LinkButton do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Link button",
    description: "A text link styled to match the button family, for navigation and low-emphasis actions.",
    components: [{Noora.Button, :link_button}],
    guidelines: [
      "Use a link button for navigation and secondary actions that should not compete with buttons, such as Learn more or Back to log in.",
      "It always renders a link. Pass `href` for regular browser navigation, `navigate` to move to another LiveView, and `patch` to update the current one.",
      "Turn on `underline` when the link sits in running text or an empty state, so it reads as a link without hovering.",
      "Pass `target=\"_blank\"` for pages outside the product, such as documentation, and add `rel` when needed.",
      "Use `secondary` for actions inside alerts and cards, and keep `destructive` for links that delete or revoke something."
    ]

  example "Variants", description: "`primary` is the default." do
    ~H"""
    <.link_button label="Back to log in" variant="primary" />
    <.link_button label="View logs" variant="secondary" />
    <.link_button label="Delete preview" variant="destructive" />
    """
  end

  example "Sizes", description: "Large is the default." do
    ~H"""
    <.link_button label="Small" size="small" />
    <.link_button label="Medium" size="medium" />
    <.link_button label="Large" size="large" />
    """
  end

  example "Underline", description: "Underlined links stand out in running text and empty states." do
    ~H"""
    <.link_button
      label="Learn more"
      size="medium"
      underline
      href="https://docs.tuist.dev"
      target="_blank"
    />
    <.link_button
      label="Get started"
      variant="secondary"
      size="medium"
      underline
      href="https://docs.tuist.dev"
      target="_blank"
    />
    """
  end

  example "With icons",
    description: "Icons sit before or after the label to show direction or that the link leaves the page." do
    ~H"""
    <.link_button label="Previous run" variant="secondary">
      <:icon_left><.chevron_left /></:icon_left>
    </.link_button>
    <.link_button label="Next run" variant="secondary">
      <:icon_right><.chevron_right /></:icon_right>
    </.link_button>
    <.link_button label="Documentation" href="https://docs.tuist.dev" target="_blank">
      <:icon_right><.external_link /></:icon_right>
    </.link_button>
    """
  end
end
