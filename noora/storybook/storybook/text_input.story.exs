defmodule TuistWeb.Storybook.TextInput do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def function, do: &Noora.TextInput.text_input/1
  def imports, do: [{Noora.Icon, user: 1}]

  def variations do
    [
      %VariationGroup{
        id: :types,
        variations: [
          %Variation{
            id: :basic,
            attributes: %{
              name: "basic",
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
              name: "email",
              placeholder: "hello@tuist.dev"
            }
          },
          %Variation{
            id: :card_number,
            attributes: %{
              type: "card_number",
              name: "card_number",
              placeholder: "0000 0000 0000 0000"
            }
          },
          %Variation{
            id: :search,
            attributes: %{
              type: "search",
              name: "search",
              placeholder: "Search..."
            }
          },
          %Variation{
            id: :password,
            attributes: %{
              name: "card_number",
              type: "password"
            }
          }
        ]
      },
      %Variation{
        id: :with_hint,
        attributes: %{
          name: "with_hint",
          placeholder: "Placeholder text...",
          suffix_hint: "Suffix text..."
        }
      },
      %Variation{
        id: :error,
        attributes: %{
          name: "error",
          placeholder: "Placeholder text...",
          suffix_hint: "Suffix text...",
          error: true
        }
      },
      %Variation{
        id: :with_custom_suffix,
        attributes: %{
          name: "with_custom_suffix",
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
          %Variation{
            id: :email,
            attributes: %{type: "email", name: "email", label: "Email", required: true}
          },
          %Variation{
            id: :password,
            attributes: %{
              type: "password",
              name: "password",
              label: "Password",
              sublabel: "(Be safe!)"
            }
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
              name: "email",
              label: "Email",
              placeholder: "hello@tuist.dev",
              suffix_hint: "This should be a valid email address ending in `@tuist.dev`.",
              disabled: true
            }
          },
          %Variation{
            id: :filled,
            attributes: %{
              type: "email",
              name: "email",
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
