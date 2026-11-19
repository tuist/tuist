defmodule TuistWeb.Noora.Pages.Alert do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Alert",
    description:
      "Communicates a status or message. Secondary alerts sit inline with the content they concern; primary alerts are raised toasts that appear in a corner of the screen.",
    components: [{Noora.Alert, :alert}],
    guidelines: [
      "Use `secondary` alerts inline, next to the content they describe, such as a form error on a sign-up page or a notice in settings.",
      "Use `primary` alerts as toasts: brief confirmations of something the person just did, such as Project created or Token copied, shown in a corner of the screen.",
      "Lead with what happened in the title, and use the description for what to do next.",
      "Match the status to the outcome: `success` confirms, `warning` asks for attention, `error` reports a failure that blocks progress.",
      "Don't rely on a toast alone for failures that need follow-up; keep an inline alert or a status on the page as well.",
      "Give dismissible alerts an `id`. Dismissing hides the element with that id."
    ]

  example "Inline",
    description:
      "Secondary alerts sit in the page, next to the content they describe. The status sets the icon and color.",
    layout: :column do
    ~H"""
    <.alert type="secondary" status="default" title="Your workspace was updated" />
    <.alert type="secondary" status="information" title="A new version of the CLI is available" />
    <.alert type="secondary" status="success" title="Your email address is confirmed" />
    <.alert type="secondary" status="warning" title="Your plan's build minutes are almost used up" />
    <.alert type="secondary" status="error" title="This email is already registered" />
    """
  end

  example "Inline sizes",
    description: "Small and medium show a single line. Large adds a description.",
    layout: :column do
    ~H"""
    <.alert type="secondary" status="information" size="small" title="Small alert" />
    <.alert type="secondary" status="information" size="medium" title="Medium alert" />
    <.alert
      type="secondary"
      status="information"
      size="large"
      title="Large alert"
      description="Large alerts have room for a description that explains what happened and what to do next."
    />
    """
  end

  example "Inline with actions", description: "One or two actions follow the title.", layout: :column do
    ~H"""
    <.alert type="secondary" status="warning" title="Your token expires in 3 days">
      <:action><.link_button size="medium" variant="secondary" label="Rotate token" /></:action>
    </.alert>
    <.alert
      type="secondary"
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

  example "Toast",
    toast: true do
    ~H"""
    <.alert id="alert-toast-default" status="success" title="Project created" dismissible />
    """
  end

  example "Toast warning", toast: true do
    ~H"""
    <.alert
      id="alert-toast-warning"
      status="warning"
      title="Your plan's build minutes are almost used up"
      dismissible
    />
    """
  end

  example "Toast error", toast: true do
    ~H"""
    <.alert
      id="alert-toast-error"
      status="error"
      title="The preview could not be uploaded"
      dismissible
    />
    """
  end

  example "Toast with action",
    toast: true do
    ~H"""
    <.alert id="alert-toast-action" status="information" title="Token copied" dismissible>
      <:action><.link_button size="medium" variant="secondary" label="View tokens" /></:action>
    </.alert>
    """
  end

  example "Toast with description",
    toast: true do
    ~H"""
    <.alert
      id="alert-toast-large"
      status="information"
      size="large"
      title="Selective testing is on"
      description="Tuist now skips tests whose dependencies did not change."
      dismissible
    />
    """
  end

  example "Toast with description and action", toast: true do
    ~H"""
    <.alert
      id="alert-toast-large-action"
      status="error"
      size="large"
      title="The build failed"
      description="Two targets failed to compile. Check the logs for details."
      dismissible
    >
      <:action><.link_button size="large" variant="secondary" label="View logs" /></:action>
    </.alert>
    """
  end

  example "Preserved toast", toast: :preserve do
    ~H"""
    <.alert
      id="alert-toast-preserved"
      status="warning"
      size="large"
      title="Your session is about to expire"
      description="You'll be signed out in 5 minutes."
      dismissible
    >
      <:action><.link_button size="large" variant="secondary" label="Stay signed in" /></:action>
    </.alert>
    """
  end
end
