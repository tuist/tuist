defmodule TuistWeb.Noora.Pages.HintText do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Hint text",
    description: "Explains what a field expects or why its value is invalid.",
    components: [{Noora.HintText, :hint_text}],
    guidelines: [
      "Text input and text area render hint text from their `hint` and `error` attributes. Add the component yourself only below controls that don't, such as a custom field.",
      "Use `destructive` for validation errors and say how to fix the value: Use only letters and numbers, rather than Invalid input.",
      "Use `disabled` below a disabled control so the hint reads as inactive too.",
      "Every variant shows the same alert icon, so the color and the wording carry the meaning.",
      "Keep hints to a sentence or two. Longer explanations belong in the page or a link to the docs."
    ]

  example "Variants",
    description: "`default` guides, `destructive` reports an error, `disabled` matches a disabled control.",
    layout: :column do
    ~H"""
    <.hint_text label="Username may only contain alphanumeric characters" />
    <.hint_text label="This handle is already taken" variant="destructive" />
    <.hint_text label="Enable Single Sign-On to configure automatic enrollment" variant="disabled" />
    """
  end

  example "Two sentences",
    description: "When a hint needs a second sentence, use it for an example or a rule of thumb.",
    layout: :column do
    ~H"""
    <.hint_text label="Jobs and pull requests from these branches also save their changes. Use * as a wildcard." />
    """
  end

  example "In inputs",
    description: "Text inputs render the hint from `hint`, and switch to the destructive variant when `error` is set.",
    layout: :column do
    ~H"""
    <.text_input
      id="hint-text-input-hint"
      name="username"
      label="Username"
      value="tuist"
      hint="Username may only contain alphanumeric characters"
    />
    <.text_input
      id="hint-text-input-error"
      name="username"
      label="Username"
      value="tuist-team"
      error="Use only letters and numbers"
    />
    """
  end
end
