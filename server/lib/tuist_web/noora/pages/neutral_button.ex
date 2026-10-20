defmodule TuistWeb.Noora.Pages.NeutralButton do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Neutral button",
    description: "A borderless button for quiet controls such as copy, close, menu, and social links.",
    components: [{Noora.Button, :neutral_button}],
    guidelines: [
      "Use a neutral button for utility controls that should stay in the background, such as copying a command, closing a panel, or opening a menu.",
      "Most neutral buttons show only an icon. Pass the icon as the inner block and give the button an `aria-label` that names the action.",
      "With `label`, the button shows the label with the `icon_left` and `icon_right` slots, and ignores the inner block.",
      "Pass `href`, `navigate`, or `patch` to render a link with the same appearance. Add `target=\"_blank\"` for external sites.",
      "For actions that need emphasis, use a button instead."
    ]

  example "Icon only", description: "The most common form. Always pass an `aria-label`." do
    ~H"""
    <.neutral_button size="large" aria-label="Copy command">
      <.copy />
    </.neutral_button>
    <.neutral_button size="large" aria-label="Search">
      <.search />
    </.neutral_button>
    <.neutral_button size="large" aria-label="Open menu">
      <.menu_2 />
    </.neutral_button>
    <.neutral_button size="large" aria-label="Close menu">
      <.close />
    </.neutral_button>
    """
  end

  example "Sizes", description: "Large is the default." do
    ~H"""
    <.neutral_button size="small" aria-label="Copy command">
      <.copy />
    </.neutral_button>
    <.neutral_button size="medium" aria-label="Copy command">
      <.copy />
    </.neutral_button>
    <.neutral_button size="large" aria-label="Copy command">
      <.copy />
    </.neutral_button>
    """
  end

  example "With label", description: "A label turns it into a quiet text button, with optional icons." do
    ~H"""
    <.neutral_button label="Small" size="small" />
    <.neutral_button label="Medium" size="medium" />
    <.neutral_button label="Copy link" size="large">
      <:icon_left><.copy /></:icon_left>
    </.neutral_button>
    """
  end

  example "As a link", description: "With `href`, `navigate`, or `patch`, it renders a link." do
    ~H"""
    <.neutral_button
      size="large"
      href="https://github.com/tuist/tuist"
      target="_blank"
      aria-label="GitHub"
    >
      <.brand_github />
    </.neutral_button>
    <.neutral_button size="large" href="https://slack.tuist.dev" target="_blank" aria-label="Slack">
      <.brand_slack />
    </.neutral_button>
    <.neutral_button
      size="large"
      href="https://bsky.app/profile/tuist.dev"
      target="_blank"
      aria-label="Bluesky"
    >
      <.brand_bluesky />
    </.neutral_button>
    """
  end

  example "Disabled" do
    ~H"""
    <.neutral_button size="large" aria-label="Copy command" disabled>
      <.copy />
    </.neutral_button>
    <.neutral_button label="Copy link" size="large" disabled>
      <:icon_left><.copy /></:icon_left>
    </.neutral_button>
    """
  end
end
