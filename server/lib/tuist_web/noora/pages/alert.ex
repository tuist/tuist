defmodule TuistWeb.Noora.Pages.Alert do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Alert",
    description: "Communicates a status or contextual message inline with the content it concerns.",
    components: [{Noora.Alert, :alert}],
    guidelines: [
      "Place an alert next to the content it describes. For messages about the whole page or account, use a banner.",
      "Lead with what happened in the title, and use the description for what to do next.",
      "Match the status to the outcome: `success` confirms, `warning` asks for attention, `error` reports a failure that blocks progress.",
      "Use the `secondary` type when several alerts stack or when the alert sits inside a card.",
      "Give dismissible alerts an `id`. Dismissing hides the element with that id."
    ]

  example "Statuses", description: "The status sets the icon and color.", layout: :column do
    ~H"""
    <.alert status="default" title="Your workspace was updated" />
    <.alert status="information" title="A new version of the CLI is available" />
    <.alert status="success" title="The cache was warmed for 128 targets" />
    <.alert status="warning" title="Your plan's build minutes are almost used up" />
    <.alert status="error" title="The preview could not be uploaded" />
    """
  end

  example "Secondary", description: "A quieter background for alerts inside cards or in a stack.", layout: :column do
    ~H"""
    <.alert type="secondary" status="information" title="A new version of the CLI is available" />
    <.alert type="secondary" status="success" title="The cache was warmed for 128 targets" />
    <.alert type="secondary" status="warning" title="Your plan's build minutes are almost used up" />
    <.alert type="secondary" status="error" title="The preview could not be uploaded" />
    """
  end

  example "Sizes", description: "Small and medium show a single line. Large adds a description.", layout: :column do
    ~H"""
    <.alert status="information" size="small" title="Small alert" />
    <.alert status="information" size="medium" title="Medium alert" />
    <.alert
      status="information"
      size="large"
      title="Large alert"
      description="Large alerts have room for a description that explains what happened and what to do next."
    />
    """
  end

  example "Actions", description: "One or two actions follow the title.", layout: :column do
    ~H"""
    <.alert status="warning" size="medium" title="Your token expires in 3 days">
      <:action><.link_button size="medium" variant="secondary" label="Rotate token" /></:action>
    </.alert>
    <.alert
      status="error"
      size="large"
      title="The build failed"
      description="Two targets failed to compile. Check the logs for details."
    >
      <:action><.link_button size="large" variant="secondary" label="View logs" /></:action>
      <:action><.link_button size="large" variant="secondary" label="Retry" /></:action>
    </.alert>
    """
  end

  example "Dismissible", description: "Shows a dismiss button that hides the alert.", layout: :column do
    ~H"""
    <.alert id="alert-dismissible-medium" status="success" title="Project created" dismissible />
    <.alert
      id="alert-dismissible-large"
      status="information"
      size="large"
      title="Selective testing is on"
      description="Tuist now skips tests whose dependencies did not change."
      dismissible
    />
    """
  end
end
