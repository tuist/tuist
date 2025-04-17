defmodule TuistWeb.Storybook.Modal do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  alias TuistWeb.Noora.Modal

  def function, do: &Modal.modal/1

  def imports,
    do: [
      {Modal, [modal_footer: 1]},
      {TuistWeb.Noora.Button, [button: 1]},
      {TuistWeb.Noora.Icon, [mail: 1]},
      {TuistWeb.Noora.Label, [label: 1]},
      {TuistWeb.Noora.TextInput, [text_input: 1]}
    ]

  def variations do
    [
      %Variation{
        id: :email_verification,
        attributes: %{
          title: "Email verification",
          description: "Enter your email for verification",
          header_size: "large",
          header_type: "icon"
        },
        slots: [
          """
          <:trigger :let={attrs}>
            <.button label="Open modal" {attrs}>Open modal</.button>
          </:trigger>
          <:header_icon>
            <.mail />
          </:header_icon>
          <.text_input id="email" name="email" value="" type="email" label="Email" required placeholder="hello@tuist.dev" />
          <:footer>
            <.modal_footer>
              <:action>
                <.button label="Cancel" variant="secondary" />
              </:action>
              <:action>
                <.button label="Save" />
              </:action>
            </.modal_footer>
          </:footer>
          """
        ]
      }
    ]
  end
end
