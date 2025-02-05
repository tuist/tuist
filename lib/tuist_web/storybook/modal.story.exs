defmodule TuistWeb.Storybook.Modal do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def function, do: &TuistWeb.Noora.Modal.modal/1

  def imports,
    do: [
      {TuistWeb.Noora.Modal, [modal_footer: 1]},
      {TuistWeb.Noora.Button, [button: 1]},
      {TuistWeb.Noora.Icon, [mail: 1]},
      {TuistWeb.Noora.Label, [label: 1]}
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

          <.label label="Email" required />
          <input type="email" placeholder="hello@tuist.dev" style="width: 100%; min-width: 360px; margin-top: 2px;" />

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
