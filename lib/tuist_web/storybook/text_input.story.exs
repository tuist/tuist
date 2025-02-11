defmodule TuistWeb.Storybook.TextInput do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def function, do: &TuistWeb.Noora.TextInput.text_input/1
  def imports, do: [{TuistWeb.Noora.Icon, user: 1}]

  def variations do
    [
      %VariationGroup{
        id: :types,
        variations: [
          %Variation{
            id: :basic,
            attributes: %{
              placeholder: "Placeholder text..."
            },
            slots: [
              """
              <:prefix>
                <.user />
              </:prefix>
              """
            ]
          },
          %Variation{
            id: :email,
            attributes: %{
              type: "email",
              placeholder: "hello@tuist.dev"
            }
          },
          %Variation{
            id: :card_number,
            attributes: %{
              type: "card_number",
              placeholder: "0000 0000 0000 0000"
            }
          },
          %Variation{
            id: :search,
            attributes: %{
              type: "search",
              placeholder: "Search..."
            }
          },
          %Variation{
            id: :password,
            attributes: %{
              type: "password"
            }
          }
        ]
      },
      %Variation{
        id: :with_hint,
        attributes: %{
          placeholder: "Placeholder text...",
          suffix_hint: "Suffix text..."
        }
      },
      %Variation{
        id: :with_custom_suffix,
        attributes: %{
          placeholder: "Placeholder text..."
        },
        slots: [
          """
          <:suffix>
            <.user/>
          </:suffix>
          """
        ]
      },
      %VariationGroup{
        id: :label,
        variations: [
          %Variation{id: :email, attributes: %{type: "email", label: "Email", required: true}},
          %Variation{
            id: :password,
            attributes: %{type: "password", label: "Password", sublabel: "(Be safe!)"}
          }
        ]
      },
      %VariationGroup{
        id: :disabled,
        variations: [
          %Variation{
            id: :unfilled,
            attributes: %{
              type: "email",
              placeholder: "hello@tuist.dev",
              suffix_hint: "This should be a valid email address ending in `@tuist.dev`.",
              disabled: true
            }
          },
          %Variation{
            id: :filled,
            attributes: %{
              type: "email",
              value: "hello@tuist.dev",
              suffix_hint: "This should be a valid email address ending in `@tuist.dev`.",
              disabled: true
            }
          }
        ]
      }
    ]
  end
end
