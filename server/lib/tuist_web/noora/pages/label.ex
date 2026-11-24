defmodule TuistWeb.Noora.Pages.Label do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Label",
    description: "Names a form control, with an optional sublabel and required indicator.",
    components: [{Noora.Label, :label}],
    guidelines: [
      "Text input and text area take `label`, `sublabel`, and `show_required` directly. Use this component above controls without a built-in label, such as a select.",
      "Additional attributes go on the inner `<label>` element. Set `for` to the id of a native control so clicking the label focuses it.",
      "`required` only shows the asterisk. Mark the control itself as required as well.",
      "Keep the label to a short noun phrase in sentence case, and move extra context into `sublabel`."
    ]

  example "Default" do
    ~H"""
    <.label label="Project name" />
    """
  end

  example "Required", description: "Adds an asterisk after the label." do
    ~H"""
    <.label label="Build system" required />
    """
  end

  example "Sublabel", description: "Secondary text that adds context without lengthening the label." do
    ~H"""
    <.label label="Name" sublabel="How this endpoint will be listed in the table." />
    <.label label="Endpoint URL" sublabel="(HTTPS only)" required />
    """
  end

  example "Disabled", description: "Matches a disabled control." do
    ~H"""
    <.label label="Organization" sublabel="(Managed by your identity provider)" required disabled />
    """
  end
end
