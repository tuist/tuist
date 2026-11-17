defmodule TuistWeb.Noora.Pages.Spinner do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Spinner",
    description: "Shows that something is loading, in place of an icon.",
    components: [{Noora.Spinner, :spinner}],
    guidelines: [
      "Use a spinner for short waits of unknown length, such as saving, deploying, or fetching.",
      "Put it where the icon would be, in a button or a badge, so the layout doesn't shift when loading starts. It takes that icon's size and the text color.",
      "Disable the button while its action is running, and keep its label, or switch it to what's happening, such as Deploying.",
      "It's announced as Loading. Pass `label` to say what's loading when the text around it doesn't.",
      "It moves like a real object: it eases over the top and is pulled quickly through the bottom, stretching like elastic, and no two laps are alike. For people who prefer reduced motion, it turns slowly at a constant speed."
    ]

  example "Default", description: "On its own it's 16px and takes the text color." do
    ~H"""
    <.spinner />
    """
  end

  example "Sizes", description: "Small, medium, and large match the 12px, 16px, and 20px icon sizes." do
    ~H"""
    <.spinner size="small" />
    <.spinner size="medium" />
    <.spinner size="large" />
    """
  end

  example "In buttons",
    description: "In an icon slot it takes the button's icon size. Disable the button while it's loading.",
    layout: :stack do
    ~H"""
    <div>
      <.button label="Deploying" variant="primary" disabled>
        <:icon_left><.spinner /></:icon_left>
      </.button>
      <.button label="Saving" variant="secondary" disabled>
        <:icon_left><.spinner /></:icon_left>
      </.button>
      <.ghost_button label="Loading" variant="secondary" disabled>
        <:icon_left><.spinner /></:icon_left>
      </.ghost_button>
      <.button icon_only variant="secondary" aria-label="Loading" disabled>
        <.spinner />
      </.button>
    </div>
    <div>
      <.button :for={size <- ~w(small medium large)} label="Saving" variant="secondary" size={size}>
        <:icon_left><.spinner /></:icon_left>
      </.button>
    </div>
    """
  end

  example "In badges", description: "In a badge's icon slot it fills the icon's box." do
    ~H"""
    <.badge :for={size <- ~w(small medium large)} label="Running" color="information" size={size}>
      <:icon><.spinner /></:icon>
    </.badge>
    <.badge label="Running" color="focus" style="light-fill" size="large">
      <:icon><.spinner /></:icon>
    </.badge>
    """
  end

  example "Label", description: "`label` names what's loading for screen readers." do
    ~H"""
    <.spinner size="large" label="Loading test results" />
    """
  end
end
