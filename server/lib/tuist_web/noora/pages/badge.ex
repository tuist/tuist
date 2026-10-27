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

  example "Variants",
    description: "Each color comes as a solid `fill` and a softer `light-fill`. `neutral` is the default color.",
    layout: :rows do
    ~H"""
    <div :for={
      color <- ~w(neutral primary secondary information focus success attention warning destructive)
    }>
      <.badge size="large" label={String.capitalize(color)} color={color} />
      <.badge size="large" label={String.capitalize(color)} color={color} style="light-fill" />
    </div>
    """
  end

  example "With icons",
    description: "An icon before the label, in every color, style, and size.",
    layout: :rows do
    ~H"""
    <div :for={
      color <- ~w(neutral primary secondary information focus success attention warning destructive)
    }>
      <.badge
        :for={size <- ~w(large medium small)}
        label={String.capitalize(color)}
        color={color}
        size={size}
      >
        <:icon><.bell /></:icon>
      </.badge>
      <.badge
        :for={size <- ~w(small medium large)}
        label={String.capitalize(color)}
        color={color}
        style="light-fill"
        size={size}
      >
        <:icon><.bell /></:icon>
      </.badge>
    </div>
    """
  end

  example "Sizes",
    description: "Small is the default. Medium suits headers and cards with more room, and large suits page headers." do
    ~H"""
    <.badge label="Small" size="small" color="primary" />
    <.badge label="Medium" size="medium" color="primary" />
    <.badge label="Large" size="large" color="primary" />
    """
  end

  example "Dot and icon", description: "A dot or an icon before the label reinforces the status at a glance." do
    ~H"""
    <.badge size="large" label="Live" color="success" style="light-fill" dot />
    <.badge size="large" label="Flaky" color="warning" style="light-fill">
      <:icon><.alert_circle /></:icon>
    </.badge>
    """
  end

  example "Disabled", description: "Ignores the color and uses the disabled presentation." do
    ~H"""
    <.badge size="large" label="Disabled" color="success" disabled />
    """
  end
end
