defmodule TuistWeb.Noora.Pages.Button do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Button",
    description:
      "Triggers an action, submits a form, or navigates to another location. A ghost button does the same for quiet utility controls.",
    components: [{Noora.Button, :button}, {Noora.Button, :ghost_button}],
    guidelines: [
      "Use a button for actions that change something, such as saving, deploying, or deleting. Pass `href`, `navigate`, or `patch` when it changes the page instead; it renders a link that looks the same.",
      "Use one primary button per surface, for the action people most likely want. Supporting actions use `secondary`.",
      "Reserve `destructive` for actions that delete or revoke something, and confirm them in a modal when they can't be undone.",
      "Use a ghost button for utility controls that should stay in the background, such as copying a command, closing a panel, or opening a menu.",
      "Name the button after what happens: Create project, Invite member, Rotate token. Avoid bare verbs such as Submit or OK.",
      "Disable a button only when the action is impossible right now, and explain why nearby or in a tooltip.",
      "While an action runs, show a spinner in the icon slot and disable the button. Keep the label, or switch it to what's happening, such as Deploying.",
      "Icon-only buttons need an `aria-label` that names the action and its target, such as Copy project URL. Don't add one to a button with a visible label; it replaces the label for screen readers.",
      "A ghost button without `label` shows its inner block, usually one icon. With `label`, it shows the label with the `icon_left` and `icon_right` slots."
    ]

  example "Variants",
    description:
      "Primary for the main action, secondary for supporting ones, destructive for actions that delete or revoke. Ghost buttons come in the same three, with no fill until hovered, for quiet utility controls, plus outline: secondary with a border.",
    layout: :stack do
    ~H"""
    <div>
      <.button label="Primary" variant="primary" />
      <.button label="Secondary" variant="secondary" />
      <.button label="Destructive" variant="destructive" />
    </div>
    <div>
      <.ghost_button label="Primary" variant="primary" />
      <.ghost_button label="Secondary" variant="secondary" />
      <.ghost_button label="Destructive" variant="destructive" />
      <.ghost_button label="Outline" variant="outline" />
    </div>
    """
  end

  example "Sizes",
    description: "Large is the default. Use medium and small in dense layouts such as table rows and toolbars." do
    ~H"""
    <.button label="Small" variant="secondary" size="small" />
    <.button label="Medium" variant="secondary" size="medium" />
    <.button label="Large" variant="secondary" size="large" />
    """
  end

  example "All variants and sizes",
    description: "Buttons and ghost buttons share their sizes, so they line up side by side.",
    layout: :stack do
    ~H"""
    <div :for={size <- ~w(small medium large)}>
      <.button
        :for={variant <- ~w(primary secondary destructive)}
        label="Demo"
        variant={variant}
        size={size}
      />
      <.ghost_button
        :for={variant <- ~w(primary secondary destructive outline)}
        label="Demo"
        variant={variant}
        size={size}
      />
    </div>
    """
  end

  example "Icons",
    description: "An icon before or after the label reinforces direction or meaning." do
    ~H"""
    <.button label="Back" variant="secondary">
      <:icon_left><.arrow_left /></:icon_left>
    </.button>
    <.button label="Continue" variant="secondary">
      <:icon_right><.arrow_right /></:icon_right>
    </.button>
    <.button label="Demo" variant="secondary">
      <:icon_left><.arrow_left /></:icon_left>
      <:icon_right><.arrow_right /></:icon_right>
    </.button>
    <.ghost_button label="Copy link" variant="secondary">
      <:icon_left><.copy /></:icon_left>
    </.ghost_button>
    <.ghost_button label="Share" variant="outline">
      <:icon_right><.external_link /></:icon_right>
    </.ghost_button>
    """
  end

  example "Icon only",
    description:
      "Square buttons for compact controls whose icon is unambiguous, at every size. Always pass an `aria-label` that names the action and its target." do
    ~H"""
    <.button
      :for={size <- ~w(small medium large)}
      icon_only
      variant="secondary"
      size={size}
      aria-label="Next page"
    >
      <.chevron_right />
    </.button>
    <.ghost_button
      :for={size <- ~w(small medium large)}
      variant="secondary"
      size={size}
      aria-label="Copy command"
    >
      <.copy />
    </.ghost_button>
    """
  end

  example "Disabled",
    description: "Every variant looks the same when disabled." do
    ~H"""
    <.button label="Primary" variant="primary" disabled />
    <.button label="Secondary" variant="secondary" disabled />
    <.button label="Destructive" variant="destructive" disabled />
    <.ghost_button label="Ghost" variant="secondary" disabled />
    <.ghost_button label="Outline" variant="outline" disabled />
    <.ghost_button variant="secondary" aria-label="Copy command" disabled>
      <.copy />
    </.ghost_button>
    """
  end

  example "Loading",
    description:
      "While an action runs, put a spinner where the icon goes and disable the button, so it can't be pressed twice.",
    layout: :stack do
    ~H"""
    <div>
      <.button :for={size <- ~w(small medium large)} label="Saving" size={size} disabled>
        <:icon_left><.spinner /></:icon_left>
      </.button>
    </div>
    <div>
      <.button label="Deploying" variant="secondary" disabled>
        <:icon_left><.spinner /></:icon_left>
      </.button>
      <.ghost_button label="Loading" variant="secondary" disabled>
        <:icon_left><.spinner /></:icon_left>
      </.ghost_button>
      <.ghost_button label="Syncing" variant="outline" disabled>
        <:icon_left><.spinner /></:icon_left>
      </.ghost_button>
      <.button icon_only variant="secondary" aria-label="Loading" disabled>
        <.spinner />
      </.button>
    </div>
    """
  end

  example "Link",
    description: "With `href`, `navigate`, or `patch`, a button or ghost button renders a link that looks the same." do
    ~H"""
    <.button label="View documentation" variant="secondary" href="https://docs.tuist.dev">
      <:icon_right><.external_link /></:icon_right>
    </.button>
    <.ghost_button
      variant="secondary"
      href="https://github.com/tuist/tuist"
      target="_blank"
      aria-label="GitHub"
    >
      <.brand_github />
    </.ghost_button>
    """
  end
end
