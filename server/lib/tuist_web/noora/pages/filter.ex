defmodule TuistWeb.Noora.Pages.Filter do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Filter",
    description: "Narrows a list or table with filters people add, edit, and remove.",
    components: [{Noora.Filter, :filter_dropdown}, {Noora.Filter, :active_filter}],
    guidelines: [
      "Describe each filter with a `Noora.Filter.Filter` struct. Its `type` sets the operators: `:option` offers is and is not, `:text` adds contains and does not contain, and `:number` compares values.",
      "Pass the same `available_filters` and `active_filters` to the filter dropdown. It lists only filters that are not active yet, and renders nothing once all of them are.",
      "Render an `active_filter` for each active filter, next to the dropdown or in a row above the table they filter.",
      "Keep filters in the URL. `Noora.Filter.Operations` encodes them as `filter_<id>_op` and `filter_<id>_val` query parameters and decodes them back into structs.",
      "Handle the `add_filter` event from the dropdown, or the event you pass as `on_select`, and the `update_filter` event that active filters send when their operator or value changes or when they are removed.",
      "Set `searchable: true` on option filters with many options to add a search input to the value menu."
    ]

  example "Filter dropdown", description: "Lists the filters people can add." do
    ~H"""
    <.filter_dropdown
      id="filter-add"
      available_filters={[
        %Noora.Filter.Filter{
          id: "status",
          display_name: "Status",
          type: :option,
          options: ["success", "failure"],
          operator: :==
        },
        %Noora.Filter.Filter{id: "git_branch", display_name: "Branch", type: :text, operator: :=~},
        %Noora.Filter.Filter{id: "duration", display_name: "Duration", type: :number, operator: :>}
      ]}
      active_filters={[]}
    />
    """
  end

  example "Option filter", description: "Option filters pick a value from a menu." do
    ~H"""
    <.active_filter filter={
      %Noora.Filter.Filter{
        id: "status",
        display_name: "Status",
        type: :option,
        options: ["success", "failure", "skipped"],
        options_display_names: %{"success" => "Passed", "failure" => "Failed", "skipped" => "Skipped"},
        operator: :==,
        value: "failure"
      }
    } />
    """
  end

  example "Text filter",
    description: "Text filters take a value in a popover. Without a value, the filter shows Enter value." do
    ~H"""
    <.active_filter filter={
      %Noora.Filter.Filter{
        id: "git_branch",
        display_name: "Branch",
        type: :text,
        operator: :=~,
        value: "main"
      }
    } />
    <.active_filter filter={
      %Noora.Filter.Filter{
        id: "module_name",
        display_name: "Module",
        type: :text,
        operator: :==,
        value: nil
      }
    } />
    """
  end

  example "Number filter", description: "Number filters compare the value with operators such as greater than." do
    ~H"""
    <.active_filter filter={
      %Noora.Filter.Filter{
        id: "duration_seconds",
        display_name: "Duration (s)",
        type: :number,
        operator: :>,
        value: "300"
      }
    } />
    """
  end

  example "With active filters",
    description:
      "The dropdown hides filters that are already active. This scheme filter sets `searchable: true`, so its value menu has a search input." do
    ~H"""
    <.active_filter filter={
      %Noora.Filter.Filter{
        id: "scheme",
        display_name: "Scheme",
        type: :option,
        options: ["App", "AppTests", "Core", "CoreTests", "Networking", "NetworkingTests"],
        options_display_names: %{},
        operator: :==,
        value: "AppTests",
        searchable: true
      }
    } />
    <.filter_dropdown
      id="filter-with-active-filters"
      available_filters={[
        %Noora.Filter.Filter{
          id: "scheme",
          display_name: "Scheme",
          type: :option,
          options: [],
          operator: :==
        },
        %Noora.Filter.Filter{
          id: "xcode_version",
          display_name: "Xcode version",
          type: :text,
          operator: :==
        },
        %Noora.Filter.Filter{
          id: "is_ci",
          display_name: "Environment",
          type: :option,
          options: ["ci", "local"],
          operator: :==
        }
      ]}
      active_filters={[%Noora.Filter.Filter{id: "scheme"}]}
    />
    """
  end
end
