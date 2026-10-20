defmodule TuistWeb.Noora.Pages.Button do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Button",
    description: "Triggers an action, submits a form, or navigates to another location.",
    components: [{Noora.Button, :button}],
    guidelines: [
      "Use one primary button per surface, for the action people most likely want. Supporting actions use `secondary`.",
      "Reserve `destructive` for actions that delete or revoke something, and confirm them in a modal when they cannot be undone.",
      "Name the button after what happens: Create project, Invite member, Rotate token. Avoid bare verbs such as Submit or OK.",
      "Pass `href`, `navigate`, or `patch` when the button changes the page. It then renders a link with the same appearance.",
      "Disable a button only when the action is impossible right now, and explain why nearby or in a tooltip.",
      "Icon-only buttons need an `aria-label` that names the action and its target, such as Copy project URL."
    ]

  example "Variants",
    description:
      "Primary for the main action, secondary for supporting ones, destructive for actions that delete or revoke." do
    ~H"""
    <.button label="Primary" variant="primary" />
    <.button label="Secondary" variant="secondary" />
    <.button label="Destructive" variant="destructive" />
    """
  end

  example "Sizes",
    description: "Large is the default. Use medium and small in dense layouts such as table rows and toolbars." do
    ~H"""
    <.button label="Small" size="small" />
    <.button label="Medium" size="medium" />
    <.button label="Large" size="large" />
    """
  end

  example "With icons", description: "Icons sit before or after the label to reinforce direction or meaning." do
    ~H"""
    <.button label="Previous" variant="secondary">
      <:icon_left><.chevron_left /></:icon_left>
    </.button>
    <.button label="Next" variant="secondary">
      <:icon_right><.chevron_right /></:icon_right>
    </.button>
    <.button label="New project">
      <:icon_left><.plus /></:icon_left>
    </.button>
    """
  end

  example "Icon only", description: "For compact controls whose icon is unambiguous. Always pass an `aria-label`." do
    ~H"""
    <.button icon_only variant="secondary" aria-label="Previous page">
      <.chevron_left />
    </.button>
    <.button icon_only variant="secondary" aria-label="Next page">
      <.chevron_right />
    </.button>
    <.button icon_only variant="destructive" aria-label="Delete project">
      <.trash />
    </.button>
    """
  end

  example "Disabled" do
    ~H"""
    <.button label="Primary" variant="primary" disabled />
    <.button label="Secondary" variant="secondary" disabled />
    <.button label="Destructive" variant="destructive" disabled />
    """
  end

  example "As a link",
    description: "With `href`, `navigate`, or `patch`, the button renders a link styled as a button." do
    ~H"""
    <.button label="View documentation" variant="secondary" href="https://docs.tuist.dev">
      <:icon_right><.external_link /></:icon_right>
    </.button>
    """
  end
end
