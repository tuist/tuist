defmodule Noora.Filter do
  @moduledoc """
  A comprehensive filtering system with dropdown and active filter components.

  ## Overview

  The filter system consists of two main components:
  - `filter_dropdown/1` - A dropdown to add new filters
  - `active_filter/1` - Displays and manages active filters

  ## Filter Configuration

  Filters are defined using the `Noora.Filter.Filter` struct with the following fields:

  - `:id` - Unique identifier for the filter (e.g., "status", "created_at")
  - `:display_name` - Human-readable name shown in the UI
  - `:type` - Filter type (`:text`, `:number`, or `:option`)
  - `:options` - List of available options (for `:option` type only)
  - `:options_display_names` - Map of option values to display names
  - `:operator` - Comparison operator (e.g., `:==`, `:=~`, `:<`)
  - `:value` - Current filter value

  ### Filter Types and Operators

  - **Text filters** (`:text`) - Support operators: `:==` (is), `:=~` (contains)
  - **Number filters** (`:number`) - Support operators: `:==`, `:<`, `:>`, `:<=`, `:>=`
  - **Option filters** (`:option`) - Support operators: `:==` (is), `:!=` (is not)
  - **List filters** (`:list`) - Support operators: `:=~` (contains), `:"!=~"` (does not contain) — for array/list fields

  ## LiveView Setup

  ### 1. Define Available Filters

  ```elixir
  @impl true
  def mount(_params, _session, socket) do
    available_filters = [
      %Noora.Filter.Filter{
        id: "status",
        display_name: "Status",
        type: :option,
        options: [:active, :inactive, :pending],
        options_display_names: %{
          active: "Active",
          inactive: "Inactive",
          pending: "Pending"
        }
      },
      %Noora.Filter.Filter{
        id: "name",
        display_name: "Name",
        type: :text
      },
      %Noora.Filter.Filter{
        id: "amount",
        display_name: "Amount",
        type: :number
      }
    ]

    {:ok, assign(socket, available_filters: available_filters, active_filters: [])}
  end
  ```

  ### 2. Handle Filter Events

  ```elixir
  @impl true
  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    # Add the selected filter with the Operations helper
    params = Noora.Filter.Operations.add_filter_to_query(filter_id, socket)
    {:noreply, push_patch(socket, to: ~p"/items?\#{params}")}
  end

  @impl true
  def handle_event("update_filter", params, socket) do
    # Update filter value or operator
    updated_params = Noora.Filter.Operations.update_filters_in_query(params, socket)
    {:noreply, push_patch(socket, to: ~p"/items?\#{updated_params}")}
  end
  ```

  ### 3. Parse Filters from URL

  ```elixir
  @impl true
  def handle_params(params, _uri, socket) do
    active_filters = Noora.Filter.Operations.decode_filters_from_query(
      params,
      socket.assigns.available_filters
    )

    {:noreply, assign(socket, active_filters: active_filters)}
  end
  ```

  ### 4. Render the Components

  ```heex
  <div class="flex gap-2">
    <.filter_dropdown
      id="add-filter"
      available_filters={@available_filters}
      active_filters={@active_filters}
      on_select="add_filter"
    />

    <.active_filter :for={filter <- @active_filters} filter={filter} />
  </div>
  ```

  ## Integration with Flop

  The filter system integrates seamlessly with Flop for query building:

  ```elixir
  def list_items(params, available_filters) do
    active_filters = Noora.Filter.Operations.decode_filters_from_query(params, available_filters)
    flop_filters = Noora.Filter.Operations.convert_filters_to_flop(active_filters)

    Flop.validate_and_run(Item, %{filters: flop_filters}, for: Item)
  end
  ```

  ## URL Parameter Format

  Filters are stored in URL parameters using the pattern:
  - `filter_{id}_op` - The operator (e.g., "==", "=~")
  - `filter_{id}_val` - The value

  Example: `?filter_status_op===&filter_status_val=active&filter_amount_op=>&filter_amount_val=100`
  """

  use Phoenix.Component

  import Noora.Button
  import Noora.Dropdown
  import Noora.Icon
  import Noora.TextInput

  alias Phoenix.LiveView.JS

  defmodule Filter do
    @moduledoc """
    Represents a filter configuration with its current state.
    ## Fields
    - `:id` - Unique identifier for the filter
    - `:display_name` - Human-readable name shown in the UI
    - `:type` - Filter type (`:text`, `:number`, or `:option`)
    - `:options` - List of available options (for `:option` type only)
    - `:options_display_names` - Map of option values to display names
    - `:operator` - Comparison operator (e.g., `:==`, `:=~`, `:<`)
    - `:value` - Current filter value
    """
    defstruct [
      :id,
      :instance_id,
      :field,
      :display_name,
      :type,
      :options,
      :options_display_names,
      :operator,
      :value
    ]

    def effective_instance_id(%__MODULE__{instance_id: nil, id: id}), do: id
    def effective_instance_id(%__MODULE__{instance_id: iid}), do: iid
  end

  defmodule Operations do
    @moduledoc false
    alias Noora.Filter.Filter

    @valid_operators [:==, :!=, :=~, :"!=~", :<, :>, :<=, :>=, :empty, :not_empty]
    @valid_actions [:change_value, :change_operator, :delete]

    def update_filters(current_filters, :change_value, params) do
      instance_id = params["payload_filter_id"]
      new_value = params["value"]

      Enum.map(current_filters, fn filter ->
        if Filter.effective_instance_id(filter) == instance_id do
          %{filter | value: new_value}
        else
          filter
        end
      end)
    end

    def update_filters(current_filters, :change_operator, params) do
      instance_id = params["payload_filter_id"]

      case coerce_operator(params["value"]) do
        nil ->
          current_filters

        new_operator ->
          Enum.map(current_filters, fn filter ->
            if Filter.effective_instance_id(filter) == instance_id,
              do: %{filter | operator: new_operator},
              else: filter
          end)
      end
    end

    def update_filters(current_filters, :delete, params) do
      instance_id = params["payload_filter_id"]
      Enum.reject(current_filters, &(Filter.effective_instance_id(&1) == instance_id))
    end

    def add_filter_to_query(filter_id, socket, params \\ nil) do
      params = params || URI.decode_query(socket.assigns.uri.query)
      filter = Enum.find(socket.assigns.available_filters, &(&1.id == filter_id))

      instance_id = next_instance_id(filter_id, params)
      filter_with_instance = %{filter | instance_id: instance_id}
      filter_params = encode_filters_to_query([filter_with_instance])

      updated_params = params |> Map.merge(filter_params) |> Map.drop(["before", "after"])
      {updated_params, instance_id}
    end

    def next_instance_id(filter_id, params) do
      existing_keys = Map.keys(params)

      if Enum.any?(existing_keys, &(&1 == "filter_#{filter_id}_op")) do
        existing_numbers =
          existing_keys
          |> Enum.flat_map(fn key ->
            case Regex.run(~r/^filter_#{Regex.escape(filter_id)}__(\d+)_(?:op|val)$/, key, capture: :all_but_first) do
              [n] -> [String.to_integer(n)]
              _ -> []
            end
          end)

        next = if Enum.empty?(existing_numbers), do: 1, else: Enum.max(existing_numbers) + 1
        "#{filter_id}__#{next}"
      else
        filter_id
      end
    end

    def update_filters_in_query(params, socket, query_params \\ nil) do
      query_params = query_params || URI.decode_query(socket.assigns.uri.query)

      current_filters =
        decode_filters_from_query(query_params, socket.assigns.available_filters)

      case coerce_action(params["type"]) do
        nil ->
          query_params

        :delete ->
          filter_id = params["payload_filter_id"]

          Map.drop(query_params, [
            "filter_#{filter_id}_op",
            "filter_#{filter_id}_val",
            # Reset pagination
            "before",
            "after"
          ])

        action ->
          updated_filters = update_filters(current_filters, action, params)
          filter_params = encode_filters_to_query(updated_filters)

          query_params
          |> Map.merge(filter_params)
          # Reset pagination
          |> Map.drop(["before", "after"])
      end
    end

    def to_flop_filter(%Filter{value: nil}), do: []
    def to_flop_filter(%Filter{value: ""}), do: []

    def to_flop_filter(%Filter{id: id, operator: operator, value: value, options_display_names: display_names})
        when is_map(display_names) and not is_nil(value) do
      option_key =
        display_names
        |> Enum.find(fn {_k, v} -> to_string(v) == to_string(value) end)
        |> case do
          {key, _} -> key
          nil -> value
        end

      [%{field: String.to_existing_atom(id), op: operator, value: option_key}]
    end

    def to_flop_filter(%Filter{field: field, operator: operator, value: value}) do
      [%{field: field, op: operator, value: value}]
    end

    def convert_filters_to_flop(filters) when is_list(filters) do
      Enum.flat_map(filters, &to_flop_filter/1)
    end

    def encode_filters_to_query(filters) when is_list(filters) do
      Enum.reduce(filters, %{}, fn filter, acc ->
        iid = Filter.effective_instance_id(filter)

        acc
        |> Map.put("filter_#{iid}_op", to_string(filter.operator))
        |> Map.put(
          "filter_#{iid}_val",
          if(is_nil(filter.value), do: "", else: to_string(filter.value))
        )
      end)
    end

    def decode_filters_from_query(params, available_filters) when is_map(params) and is_list(available_filters) do
      params
      |> extract_filter_ids()
      |> Enum.flat_map(&build_filter(&1, params, available_filters))
    end

    # Extract instance IDs from query parameters
    defp extract_filter_ids(params) do
      params
      |> Map.keys()
      |> Enum.filter(&String.starts_with?(&1, "filter_"))
      |> Enum.map(fn key ->
        Regex.run(~r/^filter_(.+)_(?:op|val)$/, key, capture: :all_but_first)
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&List.first/1)
      |> Enum.uniq()
    end

    # Build a filter from instance ID, params, and available filters
    defp build_filter(instance_id, params, available_filters) do
      base_id = Regex.replace(~r/__\d+$/, instance_id, "")

      with base_filter when not is_nil(base_filter) <-
             Enum.find(available_filters, &(&1.id == instance_id)) ||
               Enum.find(available_filters, &(&1.id == base_id)),
           op_str when not is_nil(op_str) <- params["filter_#{instance_id}_op"],
           operator when not is_nil(operator) <- coerce_operator(op_str) do
        val = normalize_value(params["filter_#{instance_id}_val"])
        processed_val = coerce_option_value(val, base_filter)

        create_filter(base_filter, operator, processed_val, instance_id)
      else
        _ -> []
      end
    end

    defp coerce_operator(op) when op in @valid_operators, do: op

    defp coerce_operator(op_str) when is_binary(op_str) do
      Enum.find(@valid_operators, fn op -> to_string(op) == op_str end)
    end

    defp coerce_operator(_), do: nil

    defp coerce_action(action_str) do
      Enum.find(@valid_actions, fn action -> to_string(action) == action_str end)
    end

    defp normalize_value(nil), do: nil
    defp normalize_value(""), do: nil
    defp normalize_value(val), do: val

    defp coerce_option_value(nil, _), do: nil

    defp coerce_option_value(val, %{type: :option} = filter) do
      case Enum.find(filter.options, fn opt -> to_string(opt) == val end) do
        nil -> val
        opt -> opt
      end
    end

    defp coerce_option_value(val, %{type: :percentage}) do
      case Float.parse(val) do
        {float_val, ""} -> float_val
        _ -> val
      end
    end

    defp coerce_option_value(val, _), do: val

    defp create_filter(base_filter, operator, val, instance_id) do
      if base_filter.type == :option && !is_nil(val) && !Enum.member?(base_filter.options, val) do
        []
      else
        [%{base_filter | operator: operator, value: val, instance_id: instance_id}]
      end
    end
  end

  attr(:available_filters, :list, required: true, doc: "List of available filters to choose from")
  attr(:active_filters, :list, required: true, doc: "List of currently active filters")
  attr(:id, :string, required: true, doc: "Unique ID for the dropdown")
  attr(:label, :string, default: "Filter", doc: "Label for the dropdown")

  attr(:on_select, :string,
    default: "add_filter",
    doc: "Event to trigger when a filter is selected"
  )

  attr(:rest, :global, doc: "Additional attributes")

  def filter_dropdown(assigns) do
    filtered_filters = filter_available_filters(assigns.available_filters, assigns.active_filters)

    if Enum.empty?(filtered_filters) do
      ~H""
    else
      assigns = assign(assigns, :filtered_filters, filtered_filters)

      ~H"""
      <.dropdown id={@id} label={@label} on_select={@on_select} {@rest}>
        <:icon><.filter /></:icon>
        <.dropdown_item
          :for={filter <- @filtered_filters}
          value={filter.id}
          label={filter.display_name}
        />
      </.dropdown>
      """
    end
  end

  defp filter_available_filters(available_filters, _active_filters) do
    available_filters
  end

  attr(:filter, Filter, required: true)

  def active_filter(assigns) do
    assigns = assign(assigns, :iid, Filter.effective_instance_id(assigns.filter))

    ~H"""
    <div id={@iid} class="noora-filter">
      <span data-part="label">{@filter.display_name}</span>
      <div
        :if={length(operators(@filter.type)) > 1}
        id={"filter-#{@iid}-operator-dropdown"}
        phx-hook="NooraDropdown"
        data-part="dropdown"
        data-on-select="update_filter"
        data-meta-type="change_operator"
        data-meta-payload_filter_id={@iid}
      >
        <div data-part="trigger">
          <span data-part="label">
            {operator_text(@filter.operator)}
          </span>
          <div data-part="indicator">
            <div data-part="indicator-down">
              <.chevron_down />
            </div>
            <div data-part="indicator-up">
              <.chevron_up />
            </div>
          </div>
        </div>
        <div data-part="positioner">
          <div class="noora-dropdown-content" data-part="content">
            <.dropdown_item
              :for={operator <- operators(@filter.type)}
              value={operator}
              label={operator_text(operator)}
            />
          </div>
        </div>
      </div>
      <span :if={length(operators(@filter.type)) == 1} data-part="label">
        {operator_text(@filter.operator)}
      </span>
      <div
        :if={@filter.type === :option}
        id={"filter-#{@iid}-value-dropdown"}
        phx-hook="NooraDropdown"
        data-part="dropdown"
        data-on-select="update_filter"
        data-meta-type="change_value"
        data-meta-payload_filter_id={@iid}
      >
        <div data-part="trigger">
          <span :if={!is_nil(@filter.value)} data-part="badge">
            {get_display_value(@filter)}
          </span>
          <span :if={is_nil(@filter.value)} data-part="placeholder">
            Enter value
          </span>
          <div data-part="indicator">
            <div data-part="indicator-down">
              <.chevron_down />
            </div>
            <div data-part="indicator-up">
              <.chevron_up />
            </div>
          </div>
        </div>
        <div data-part="positioner">
          <div class="noora-dropdown-content" data-part="content">
            <.dropdown_item
              :for={option <- @filter.options}
              value={option}
              label={Map.get(@filter.options_display_names, option, to_string(option))}
            />
          </div>
        </div>
      </div>
      <div
        :if={@filter.type !== :option}
        id={"filter-#{@iid}-value-popover"}
        phx-hook="NooraPopover"
        data-part="popover"
      >
        <div data-part="trigger">
          <span :if={!is_nil(@filter.value)} data-part="badge">
            {get_display_value(@filter)}
          </span>
          <span :if={is_nil(@filter.value)} data-part="placeholder">
            Enter value
          </span>
          <div data-part="indicator">
            <.chevron_down />
          </div>
        </div>
        <div data-part="positioner">
          <div data-part="content">
            <span>Filter by {@filter.display_name}</span>
            <form phx-submit="update_filter">
              <input type="hidden" name="type" value="change_value" />
              <input type="hidden" name="payload_filter_id" value={@iid} />
              <.text_input
                name="value"
                type="basic"
                input_type={
                  case @filter.type do
                    :number -> "number"
                    :percentage -> "number"
                    _ -> nil
                  end
                }
                min={
                  case @filter.type do
                    :number -> 0
                    :percentage -> 0
                    _ -> nil
                  end
                }
                max={
                  case @filter.type do
                    :percentage -> 100
                    _ -> nil
                  end
                }
                step={
                  case @filter.type do
                    :number -> 1
                    :percentage -> 0.1
                    _ -> nil
                  end
                }
                value={@filter.value}
                phx-hook="PlaceCursorAtEnd"
              />
              <div data-part="actions">
                <.button
                  type="button"
                  variant="secondary"
                  label="Cancel"
                  phx-click={
                    JS.dispatch("phx:close-popover",
                      detail: %{id: "filter-#{@iid}-value-popover"}
                    )
                  }
                />
                <.button type="submit" label="Apply" />
              </div>
            </form>
          </div>
        </div>
      </div>
      <button
        data-part="delete-icon"
        phx-click="update_filter"
        phx-value-type="delete"
        phx-value-payload_filter_id={@iid}
      >
        <.trash_x />
      </button>
    </div>
    """
  end

  defp operators(:option), do: [:==, :!=]
  defp operators(:text), do: [:==, :=~]
  defp operators(:number), do: [:==, :<, :>, :<=, :>=]
  defp operators(:percentage), do: [:==, :<, :>, :<=, :>=]
  defp operators(:list), do: [:=~, :"!=~"]

  def operator_text(:==), do: "is"
  def operator_text(:!=), do: "is not"
  def operator_text(:=~), do: "contains"
  def operator_text(:"!=~"), do: "does not contain"
  def operator_text(:<), do: "less than"
  def operator_text(:>), do: "greater than"
  def operator_text(:<=), do: "less than or equal to"
  def operator_text(:>=), do: "greater than or equal to"
  def operator_text(operator), do: to_string(operator)

  defp get_display_value(%Filter{type: :option, value: value, options_display_names: display_names})
       when is_map(display_names) and not is_nil(value) do
    # Value could be an atom, integer, or string
    Map.get(display_names, value, value)
  end

  defp get_display_value(%Filter{value: value}), do: value
end
