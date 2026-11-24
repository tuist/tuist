defmodule TuistWeb.Noora.Pages.DigitInput do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Digit input",
    description: "Collects a short code one character per box, such as a one-time verification code.",
    components: [{Noora.TextInput, :digit_input}],
    guidelines: [
      "Set `otp` for one-time codes so browsers and password managers can fill the code in.",
      "Match `type` to the characters the code can contain. Characters of another type are rejected.",
      "The digit input doesn't submit with a form. Read the code from the `on_complete` event, which receives `value` as a list and `valueAsString` as one string.",
      "Set `error` when the code is wrong, and explain what to do next in the text around the input.",
      "Focus leaves the input once every box is filled, so handle `on_complete` instead of waiting for a submit."
    ]

  example "Types",
    description: "`numeric` is the default. `alphanumeric` and `alphabetic` accept letters.",
    layout: :column do
    ~H"""
    <.digit_input id="digit-input-numeric" characters={6} placeholder="•" />
    <.digit_input id="digit-input-alphanumeric" type="alphanumeric" characters={6} placeholder="•" />
    <.digit_input id="digit-input-alphabetic" type="alphabetic" characters={4} placeholder="•" />
    """
  end

  example "One-time code", description: "With `otp`, browsers can fill in a code received by email or text message." do
    ~H"""
    <.digit_input
      id="digit-input-otp"
      characters={6}
      otp
      placeholder="•"
      on_complete="verify_code"
    />
    """
  end

  example "Lengths", description: "`characters` sets the number of boxes.", layout: :column do
    ~H"""
    <.digit_input id="digit-input-length-4" characters={4} placeholder="•" />
    <.digit_input id="digit-input-length-8" characters={8} placeholder="•" />
    """
  end

  example "Error" do
    ~H"""
    <.digit_input id="digit-input-error" characters={6} placeholder="•" error />
    """
  end

  example "Disabled" do
    ~H"""
    <.digit_input id="digit-input-disabled" characters={6} placeholder="•" disabled />
    """
  end
end
