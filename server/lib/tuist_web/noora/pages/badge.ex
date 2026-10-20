defmodule TuistWeb.Noora.Pages.Badge do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Badge",
    description: "Labels an item with a short status or category.",
    components: [{Noora.Badge, :badge}],
    guidelines: [
      "Keep labels to one or two words. A badge annotates something else and should not carry a sentence.",
      "Pick the color for its meaning, not for decoration: `success` for healthy or passing, `destructive` for failures, `warning` and `attention` for things that need a look.",
      "Use `light-fill` when several badges sit together, so the row stays calm. Save `fill` for the one that needs attention.",
      "For run and job states, use the status badge, which pairs each state with a consistent icon."
    ]

  example "Colors", description: "Each color carries a meaning. `neutral` is the default." do
    ~H"""
    <.badge label="Neutral" color="neutral" />
    <.badge label="Primary" color="primary" />
    <.badge label="Secondary" color="secondary" />
    <.badge label="Information" color="information" />
    <.badge label="Focus" color="focus" />
    <.badge label="Success" color="success" />
    <.badge label="Attention" color="attention" />
    <.badge label="Warning" color="warning" />
    <.badge label="Destructive" color="destructive" />
    """
  end

  example "Light fill", description: "A softer background for badges that appear in groups or tables." do
    ~H"""
    <.badge label="Neutral" color="neutral" style="light-fill" />
    <.badge label="Primary" color="primary" style="light-fill" />
    <.badge label="Information" color="information" style="light-fill" />
    <.badge label="Success" color="success" style="light-fill" />
    <.badge label="Warning" color="warning" style="light-fill" />
    <.badge label="Destructive" color="destructive" style="light-fill" />
    """
  end

  example "Sizes", description: "Small is the default. Large suits headers and cards with more room." do
    ~H"""
    <.badge label="Small" size="small" color="primary" />
    <.badge label="Large" size="large" color="primary" />
    """
  end

  example "Dot and icon", description: "A dot or an icon before the label reinforces the status at a glance." do
    ~H"""
    <.badge label="Live" color="success" style="light-fill" dot />
    <.badge label="Flaky" color="warning" style="light-fill">
      <:icon><.alert_circle /></:icon>
    </.badge>
    <.badge label="Large" color="success" style="light-fill" size="large" dot />
    """
  end

  example "Icon only", description: "For tight spaces. The label is not rendered, so pass an `aria-label`." do
    ~H"""
    <.badge label="Warning" icon_only color="warning" style="light-fill" aria-label="Warning">
      <:icon><.alert_circle /></:icon>
    </.badge>
    <.badge
      label="Warning"
      icon_only
      size="large"
      color="warning"
      style="light-fill"
      aria-label="Warning"
    >
      <:icon><.alert_circle /></:icon>
    </.badge>
    """
  end

  example "Disabled", description: "Ignores the color and uses the disabled presentation." do
    ~H"""
    <.badge label="Disabled" color="success" disabled />
    <.badge label="Disabled" color="success" style="light-fill" disabled />
    """
  end
end
