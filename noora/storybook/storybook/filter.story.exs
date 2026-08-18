defmodule TuistWeb.Storybook.Filter do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  alias Noora.Filter.Filter

  defmodule Example do
    @moduledoc false
    use Phoenix.Component

    import Noora.Filter

    attr(:id, :string, required: true)
    attr(:available_filters, :list, required: true)
    attr(:active_filters, :list, required: true)

    def filter(assigns) do
      ~H"""
      <div
        data-part="filter-example"
        style="display: flex; flex-wrap: wrap; gap: var(--noora-spacing-3);"
      >
        <.active_filter :for={filter <- @active_filters} filter={filter} />
        <.filter_dropdown
          id={@id}
          available_filters={@available_filters}
          active_filters={@active_filters}
          on_select={nil}
        />
      </div>
      """
    end
  end

  def function, do: &Example.filter/1

  def variations do
    available_filters = [
      %Filter{
        id: "status",
        display_name: "Status",
        type: :option,
        options: [:active, :paused],
        options_display_names: %{active: "Active", paused: "Paused"},
        operator: :==,
        value: :active
      },
      %Filter{
        id: "name",
        display_name: "Name",
        type: :text,
        operator: :==,
        value: nil
      },
      %Filter{
        id: "amount",
        display_name: "Amount",
        type: :number,
        operator: :==,
        value: nil
      }
    ]

    [
      %Variation{
        id: :default,
        description: "An active status filter with additional filters available",
        attributes: %{
          id: "filter-status",
          available_filters: available_filters,
          active_filters: [hd(available_filters)]
        }
      },
      %Variation{
        id: :empty,
        description: "The filter selector without active filters",
        attributes: %{
          id: "filter-empty",
          available_filters: available_filters,
          active_filters: []
        }
      },
      %Variation{
        id: :text,
        description: "A text filter with a value",
        attributes: %{
          id: "filter-text",
          available_filters: available_filters,
          active_filters: [
            %Filter{
              id: "name",
              display_name: "Name",
              type: :text,
              operator: :==,
              value: "Tuist"
            }
          ]
        }
      }
    ]
  end
end
