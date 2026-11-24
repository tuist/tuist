defmodule TuistWeb.Noora.Pages.TextInput do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Text input",
    description: "Collects a single line of text, such as a name, an email, a URL, or a search query.",
    components: [{Noora.TextInput, :text_input}],
    guidelines: [
      ~s(`type` sets the prefix icon and the suffix, while `input_type` sets the HTML input type, which defaults to `text`. Pair `type="password"` with `input_type="password"` so the value is masked, and `type="email"` with `input_type="email"` for the email keyboard and validation.),
      "Inside a form, pass `field`. The input then takes its id, name, value, and first error from the form field.",
      "`error` replaces the hint and outlines the input. Pass `show_error_message={false}` to keep the outline without the message.",
      "`required` sets the HTML attribute. Add `show_required` to also show the asterisk next to the label.",
      "The `search` type shows a ⌘K shortcut but does not bind it. Pass `show_suffix={false}` when nothing on the page listens for it.",
      "For other HTML input types, such as `date` or `number`, keep `type` as `basic` and set `input_type`. Number inputs also take `min`, `max`, and `step`."
    ]

  example "Types",
    description: "`type` sets the prefix icon and the suffix. `input_type` sets the HTML input type.",
    layout: :column do
    ~H"""
    <.text_input id="text-input-type-basic" name="project" placeholder="ios-app" />
    <.text_input
      id="text-input-type-email"
      type="email"
      input_type="email"
      name="email"
      placeholder="hello@tuist.dev"
    />
    <.text_input
      id="text-input-type-search"
      type="search"
      name="search"
      placeholder="Search projects"
    />
    <.text_input id="text-input-type-password" type="password" input_type="password" name="password" />
    <.text_input
      id="text-input-type-card-number"
      type="card_number"
      name="card_number"
      placeholder="0000 0000 0000 0000"
    />
    """
  end

  example "Label and hint",
    description: "`label` and `sublabel` sit above the input and `hint` below it.",
    layout: :column do
    ~H"""
    <.text_input
      id="text-input-label-hint"
      name="username"
      label="Username"
      sublabel="(Shown in your project URLs)"
      placeholder="tuist"
      hint="Username may only contain alphanumeric characters"
      required
      show_required
    />
    """
  end

  example "Error", description: "`error` takes the place of the hint.", layout: :column do
    ~H"""
    <.text_input
      id="text-input-error"
      type="email"
      input_type="email"
      name="email"
      label="Email"
      value="marek@tuist"
      error="Enter a valid email address"
    />
    """
  end

  example "Prefix and suffix",
    description: "Custom content before and after the value, or a tooltip with `suffix_hint`.",
    layout: :column do
    ~H"""
    <.text_input
      id="text-input-prefix"
      name="endpoint_url"
      label="Endpoint URL"
      placeholder="https://hooks.example.com/tuist"
    >
      <:prefix><.world /></:prefix>
    </.text_input>
    <.text_input id="text-input-suffix" name="branch" label="Default branch" value="main">
      <:suffix><.git_branch /></:suffix>
    </.text_input>
    <.text_input
      id="text-input-suffix-hint"
      name="token"
      label="Project token"
      placeholder="tuist_"
      suffix_hint="Create a token with tuist project tokens create."
    />
    """
  end

  example "Disabled", layout: :column do
    ~H"""
    <.text_input
      id="text-input-disabled"
      type="email"
      input_type="email"
      name="email"
      label="Email"
      value="hello@tuist.dev"
      disabled
    />
    """
  end

  example "With a form field",
    description: "With `field`, the name, value, and error come from the form.",
    layout: :column do
    ~H"""
    <.form
      :let={f}
      for={to_form(%{"handle" => "tuist"}, errors: [handle: {"has already been taken", []}])}
    >
      <.text_input id="text-input-field" field={f[:handle]} label="Organization handle" />
    </.form>
    """
  end
end
