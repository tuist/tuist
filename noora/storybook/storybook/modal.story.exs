defmodule TuistWeb.Storybook.Modal do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  alias Noora.Modal

  def function, do: &Modal.modal/1

  def imports,
    do: [
      {Modal, [modal_footer: 1]},
      {Noora.Button, [button: 1]},
      {Noora.Icon, [mail: 1]},
      {Noora.Label, [label: 1]},
      {Noora.TextInput, [text_input: 1]}
    ]

  def variations do
    [
      %VariationGroup{
        id: :header_types,
        description: "Different header types with corresponding icons and styling",
        variations: [
          %Variation{
            id: :default,
            attributes: %{
              id: "modal-header-default",
              title: "Default Modal",
              description: "A standard modal with default header styling",
              header_type: "default",
              header_size: "large"
            },
            slots: [
              """
              <:trigger :let={attrs}>
                <.button label="Default Modal" {attrs} />
              </:trigger>
              <p>This is a basic modal with default header styling.</p>
              <:footer>
                <.modal_footer>
                  <:action>
                    <.button label="Cancel" variant="secondary" />
                  </:action>
                  <:action>
                    <.button label="Confirm" />
                  </:action>
                </.modal_footer>
              </:footer>
              """
            ]
          },
          %Variation{
            id: :icon,
            attributes: %{
              id: "modal-header-icon",
              title: "Custom Icon Modal",
              description: "Modal with custom icon in header",
              header_type: "icon",
              header_size: "large"
            },
            slots: [
              """
              <:trigger :let={attrs}>
                <.button label="Icon Modal" {attrs} />
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
                    <.button label="Send" />
                  </:action>
                </.modal_footer>
              </:footer>
              """
            ]
          },
          %Variation{
            id: :success,
            attributes: %{
              id: "modal-header-success",
              title: "Success",
              description: "Operation completed successfully",
              header_type: "success",
              header_size: "large"
            },
            slots: [
              """
              <:trigger :let={attrs}>
                <.button label="Success Modal" {attrs} />
              </:trigger>
              <p>Your operation has been completed successfully!</p>
              <:footer>
                <.modal_footer>
                  <:action>
                    <.button label="Close" />
                  </:action>
                </.modal_footer>
              </:footer>
              """
            ]
          },
          %Variation{
            id: :info,
            attributes: %{
              id: "modal-header-info",
              title: "Information",
              description: "Important information about this action",
              header_type: "info",
              header_size: "large"
            },
            slots: [
              """
              <:trigger :let={attrs}>
                <.button label="Info Modal" {attrs} />
              </:trigger>
              <p>Here's some important information you should know before proceeding.</p>
              <:footer>
                <.modal_footer>
                  <:action>
                    <.button label="Got it" />
                  </:action>
                </.modal_footer>
              </:footer>
              """
            ]
          },
          %Variation{
            id: :warning,
            attributes: %{
              id: "modal-header-warning",
              title: "Warning",
              description: "This action requires your attention",
              header_type: "warning",
              header_size: "large"
            },
            slots: [
              """
              <:trigger :let={attrs}>
                <.button label="Warning Modal" {attrs} />
              </:trigger>
              <p>This action may have consequences. Please review before continuing.</p>
              <:footer>
                <.modal_footer>
                  <:action>
                    <.button label="Cancel" variant="secondary" />
                  </:action>
                  <:action>
                    <.button label="Continue" variant="destructive" />
                  </:action>
                </.modal_footer>
              </:footer>
              """
            ]
          },
          %Variation{
            id: :error,
            attributes: %{
              id: "modal-header-error",
              title: "Error",
              description: "Something went wrong",
              header_type: "error",
              header_size: "large"
            },
            slots: [
              """
              <:trigger :let={attrs}>
                <.button label="Error Modal" {attrs} />
              </:trigger>
              <p>An error occurred while processing your request. Please try again.</p>
              <:footer>
                <.modal_footer>
                  <:action>
                    <.button label="Retry" />
                  </:action>
                </.modal_footer>
              </:footer>
              """
            ]
          }
        ]
      },
      %VariationGroup{
        id: :header_sizes,
        description: "Header size variations affecting title and description layout",
        variations: [
          %Variation{
            id: :small,
            attributes: %{
              id: "modal-header-small",
              title: "Small Header",
              description: "This description won't be shown because header size is small",
              header_type: "default",
              header_size: "small"
            },
            slots: [
              """
              <:trigger :let={attrs}>
                <.button label="Small Header" {attrs} />
              </:trigger>
              <p>Modal with small header - description is not displayed.</p>
              <:footer>
                <.modal_footer>
                  <:action>
                    <.button label="Close" />
                  </:action>
                </.modal_footer>
              </:footer>
              """
            ]
          },
          %Variation{
            id: :large,
            attributes: %{
              id: "modal-header-large",
              title: "Large Header",
              description: "This description is visible because header size is large",
              header_type: "default",
              header_size: "large"
            },
            slots: [
              """
              <:trigger :let={attrs}>
                <.button label="Large Header" {attrs} />
              </:trigger>
              <p>Modal with large header - description is displayed below the title.</p>
              <:footer>
                <.modal_footer>
                  <:action>
                    <.button label="Close" />
                  </:action>
                </.modal_footer>
              </:footer>
              """
            ]
          }
        ]
      },
      %VariationGroup{
        id: :footer_variations,
        description: "Different footer configurations and button arrangements",
        variations: [
          %Variation{
            id: :no_footer,
            attributes: %{
              id: "modal-no-footer",
              title: "Modal Without Footer",
              description: "This modal has no footer section",
              header_type: "default",
              header_size: "large"
            },
            slots: [
              """
              <:trigger :let={attrs}>
                <.button label="No Footer" {attrs} />
              </:trigger>
              <p>This modal doesn't have a footer. Users can close it using the X button in the header.</p>
              """
            ]
          },
          %Variation{
            id: :single_action,
            attributes: %{
              id: "modal-single-action",
              title: "Single Action",
              description: "Modal with only one action button",
              header_type: "success",
              header_size: "large"
            },
            slots: [
              """
              <:trigger :let={attrs}>
                <.button label="Single Action" {attrs} />
              </:trigger>
              <p>This modal has only one action in the footer.</p>
              <:footer>
                <.modal_footer>
                  <:action>
                    <.button label="Got it" />
                  </:action>
                </.modal_footer>
              </:footer>
              """
            ]
          },
          %Variation{
            id: :multiple_actions,
            attributes: %{
              id: "modal-multiple-actions",
              title: "Multiple Actions",
              description: "Modal with several action buttons",
              header_type: "warning",
              header_size: "large"
            },
            slots: [
              """
              <:trigger :let={attrs}>
                <.button label="Multiple Actions" {attrs} />
              </:trigger>
              <p>This modal demonstrates multiple action buttons in the footer.</p>
              <:footer>
                <.modal_footer>
                  <:action>
                    <.button label="Save Draft" variant="secondary" />
                  </:action>
                  <:action>
                    <.button label="Cancel" variant="secondary" />
                  </:action>
                  <:action>
                    <.button label="Publish" />
                  </:action>
                </.modal_footer>
              </:footer>
              """
            ]
          }
        ]
      }
    ]
  end
end
