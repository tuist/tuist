defmodule TuistWeb.Noora.Pages.Badge do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Badge",
    description:
      "Labels an item with a short category or status. The status badge shows the state of a build, test run, or job with a consistent icon and color.",
    components: [{Noora.Badge, :badge}, {Noora.Badge, :status_badge}],
    guidelines: [
      "Keep labels to one or two words. A badge annotates something else and should not carry a sentence.",
      "Pick the color for its meaning, not for decoration: `success` for healthy or passing, `destructive` for failures, `warning` and `attention` for things that need a look.",
      "Use `light-fill` when several badges sit together, so the row stays calm. Save `fill` for the one that needs attention.",
      "For run and job states, use the status badge, which pairs each state with a consistent icon.",
      "Map each outcome to the same status everywhere: `success` for passed, `error` for failed, `warning` for cancelled, `in_progress` for running.",
      "The status sets the status badge's icon and its color, and `disabled` also mutes the label. Write the label for the outcome, such as Passed or Failed.",
      "Use `type=\"dot\"` in dense lists where the status icons would compete with the content."
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

  example "Status badge", description: "Each status has its own icon." do
    ~H"""
    <.status_badge status="success" label="Passed" />
    <.status_badge status="error" label="Failed" />
    <.status_badge status="warning" label="Cancelled" />
    <.status_badge status="attention" label="Flaky" />
    <.status_badge status="in_progress" label="Running" />
    <.status_badge status="disabled" label="Skipped" />
    """
  end

  example "Status badge with a dot",
    description: "`type=\"dot\"` replaces the icon with a dot in the status color." do
    ~H"""
    <.status_badge type="dot" status="success" label="Passed" />
    <.status_badge type="dot" status="error" label="Failed" />
    <.status_badge type="dot" status="warning" label="Cancelled" />
    <.status_badge type="dot" status="attention" label="Flaky" />
    <.status_badge type="dot" status="in_progress" label="Running" />
    <.status_badge type="dot" status="disabled" label="Skipped" />
    """
  end
end
