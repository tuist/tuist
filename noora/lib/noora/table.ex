defmodule Noora.Table do
  @moduledoc """
  Noora's table component.

  The table component is used to display data in a tabular format. It supports various types of cells, such as text, badges, and buttons.

  ## Usage

  The component expects its content to be passed as a list of rows or a LiveView stream as the `rows` attribute. Each row is a map with its
  values.
  Columns are defined using the `col` slot, which takes a label and an optional icon. Inside the columns, a large number of different cells
  are supported.

  ## Example

  ### Basic table

  ```
  <.table
    id="table-single-cell-types"
    rows={[%{id: 1, label: "Row One", status: "error"}, %{id: 2, label: "Row Two", status: "success"}]}
  >
    <:col :let={i} label="Text">
      <.text_cell label={i.label} sublabel="(Internal)" icon="alert_circle" />
    </:col>
    <:col :let={i} label="Status badge">
      <.status_badge_cell label={i.status} status={i.status />
    </:col>
  </.table>
  ```

  ### Expandable rows

  Tables can have expandable rows that reveal additional content when clicked. Use the `row_expandable` attribute to determine which rows can be expanded,
  and the `expanded_content` slot to define what content to show.

  ```
  <.table
    id="expandable-table"
    rows={@tasks}
    row_key={fn task -> task.key end}
    row_expandable={fn task -> not Enum.empty?(task.details) end}
    expanded_rows={MapSet.to_list(@expanded_task_keys)}
  >
    <:col :let={task} label="Task">
      <.text_cell label={task.description} />
    </:col>
    <:col :let={task} label="Status">
      <.badge_cell label={task.status} color="success" />
    </:col>
    <:expanded_content :let={task}>
      <div>
        <%= for detail <- task.details do %>
          <p>{detail}</p>
        <% end %>
      </div>
    </:expanded_content>
  </.table>
  ```

  In your LiveView, handle the expand/collapse interaction:

  ```
  def handle_event("toggle-expand", %{"row-key" => row_key}, socket) do
    expanded_keys = socket.assigns.expanded_task_keys

    updated_keys =
      if MapSet.member?(expanded_keys, row_key) do
        MapSet.delete(expanded_keys, row_key)
      else
        MapSet.put(expanded_keys, row_key)
      end

    {:noreply, assign(socket, expanded_task_keys: updated_keys)}
  end
  ```
  """

  use Phoenix.Component

  import Noora.Badge
  import Noora.Button
  import Noora.Icon
  import Noora.Tag
  import Noora.Time
  import Noora.Utils

  attr(:id, :string, required: true, doc: "A uniqie identifier for the table")

  attr(:rows, :list, required: true, doc: "The table content")

  attr(:row_key, :fun,
    default: nil,
    doc:
      "A function to generate the row key. Required when using a LiveView stream. If using streams and not provided, defaults to the `id` key of the stream."
  )

  attr(:row_navigate, :fun,
    default: nil,
    doc: "A function to generate the link to navigate to when clicking on a row."
  )

  attr(:row_click, :fun,
    default: nil,
    doc: "A function to generate the click handler for a row."
  )

  attr(:row_expandable, :fun,
    default: nil,
    doc: "A function to determine if a row can be expanded. Returns true/false."
  )

  attr(:expanded_rows, :list,
    default: [],
    doc: "A list of row keys/IDs that are currently expanded."
  )

  slot(:empty_state, required: false)

  slot :col, required: true do
    attr(:label, :string, required: false, doc: "The label of the column")
    attr(:icon, :string, doc: "An icon to render next to the label")
    attr(:patch, :string, doc: "A patch to apply to the column")
  end

  slot(:expanded_content, required: false, doc: "Content to display when a row is expanded")

  def table(assigns) do
    assigns =
      case assigns do
        %{rows: %Phoenix.LiveView.LiveStream{}} ->
          assign(assigns,
            row_key: assigns.row_key || fn {id, _item} -> id end
          )

        _ ->
          assign(assigns,
            row_key:
              assigns.row_key ||
                fn row ->
                  key = Map.get(row, :id)
                  if is_binary(key), do: key, else: "#{assigns.id}-row-#{key}"
                end
          )
      end

    ~H"""
    <div id={@id} class="noora-table">
      <table>
        <thead>
          <tr>
            <th :for={col <- @col}>
              <%= if col[:patch] do %>
                <.link patch={col[:patch]} data-part="sort-link">
                  <span>{col[:label]}</span>
                  <span :if={col[:icon]} data-part="icon"><.icon name={col[:icon]} /></span>
                </.link>
              <% else %>
                <span>{col[:label]}</span>
                <span :if={col[:icon]} data-part="icon"><.icon name={col[:icon]} /></span>
              <% end %>
            </th>
          </tr>
        </thead>
        <tbody
          id={"#{@id}-body"}
          phx-update={match?(%Phoenix.LiveView.LiveStream{}, @rows) && "stream"}
        >
          <%= for row <- @rows do %>
            <% row_key = @row_key && @row_key.(row) %>
            <% is_expandable = @row_expandable && @row_expandable.(row) %>
            <% is_expanded = row_key in @expanded_rows %>

            <tr
              id={row_key}
              {if is_expandable,
               do: %{
                 "phx-click" => "toggle-expand",
                 "phx-value-row-key" => row_key
               },
               else: if(@row_click, do: @row_click.(row) || %{}, else: %{})}
              data-expandable={is_expandable}
              data-expanded={is_expanded}
            >
              <td
                :for={{col, index} <- Enum.with_index(@col)}
                data-selectable={
                  !is_expandable &&
                    (not is_nil(@row_navigate) or
                       (not is_nil(@row_click) && not is_nil(@row_click.(row))))
                }
              >
                <%= if is_expandable && index == 0 do %>
                  <div data-part="expand-cell">
                    <.chevron_down :if={is_expanded} />
                    <.chevron_right :if={!is_expanded} />
                    {render_slot(col, row)}
                  </div>
                <% else %>
                  <%= if @row_navigate do %>
                    <.link navigate={@row_navigate.(row)} data-part="link">
                      {render_slot(col, row)}
                    </.link>
                  <% else %>
                    {render_slot(col, row)}
                  <% end %>
                <% end %>
              </td>
            </tr>

            <tr :if={is_expandable && is_expanded} data-part="expanded-row" id={"#{row_key}-expanded"}>
              <td colspan={length(@col)} data-part="expanded-content">
                {render_slot(@expanded_content, row)}
              </td>
            </tr>
          <% end %>

          <tr :if={has_slot_content?(@empty_state, assigns) && Enum.empty?(@rows)}>
            <td colspan={length(@col)}>
              {render_slot(@empty_state)}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr(:label, :string, default: nil, doc: "The label of the cell")

  attr(:icon, :string,
    default: nil,
    doc: "An optional icon to render next to the label. Mutually exclusive with `image`."
  )

  attr(:sublabel, :string, default: nil, doc: "An optional sublabel")

  attr(:rest, :global)

  slot(:image,
    required: false,
    doc: "An optional image to render next to the label. Mutually exclusive with `icon`. Takes precedence over `icon`."
  )

  def text_cell(assigns) do
    ~H"""
    <div data-part="cell" data-type="text" {@rest}>
      <div :if={@icon || has_slot_content?(@image, assigns)} data-part="icon">
        <.icon :if={@icon && !has_slot_content?(@image, assigns)} name={@icon} />
        <%= if has_slot_content?(@image, assigns) do %>
          {render_slot(@image)}
        <% end %>
      </div>
      <span :if={@label} data-part="label">{@label}</span>
      <span :if={@sublabel} data-part="sublabel">{@sublabel}</span>
    </div>
    """
  end

  attr(:label, :string, default: nil, doc: "The label of the cell")

  attr(:icon, :string,
    default: nil,
    doc: "An optional icon to render next to the label. Mutually exclusive with `image`."
  )

  attr(:description, :string, default: nil, doc: "The description of the cell")
  attr(:secondary_description, :string, default: nil, doc: "The secondary description of the cell")
  attr(:rest, :global)

  slot(:image,
    required: false,
    doc: "An optional image to render next to the label. Takes precedence over `icon`."
  )

  def text_and_description_cell(assigns) do
    ~H"""
    <div data-part="cell" data-type="text_and_description" {@rest}>
      <div :if={@icon || has_slot_content?(@image, assigns)} data-part="icon">
        <.icon :if={@icon && !has_slot_content?(@image, assigns)} name={@icon} />
        <%= if has_slot_content?(@image, assigns) do %>
          {render_slot(@image)}
        <% end %>
      </div>
      <div data-part="column">
        <span data-part="label">{@label}</span>
        <span data-part="description">
          {@description}
          <span :if={@secondary_description} data-part="dot">•</span>
          <span :if={@secondary_description} data-part="secondary_description">
            {@secondary_description}
          </span>
        </span>
      </div>
    </div>
    """
  end

  attr(:label, :string, default: nil, doc: "The label of the badge")

  attr(:icon, :string,
    default: nil,
    doc: "An optional icon to render next to the label."
  )

  attr(:style, :string,
    values: ~w(fill light-fill),
    default: "fill",
    doc: "The style of the badge"
  )

  attr(:color, :string,
    values: ~w(neutral destructive warning attention success information focus primary secondary),
    default: "neutral",
    doc: "The color of the badge"
  )

  attr(:rest, :global)

  def badge_cell(assigns) do
    ~H"""
    <div data-part="cell" data-type="badge" {@rest}>
      <.badge style={@style} color={@color} size="large" label={@label}>
        <:icon :if={@icon}>
          <.icon name={@icon} />
        </:icon>
      </.badge>
    </div>
    """
  end

  attr(:label, :string, default: nil, doc: "The label of the badge")

  attr(:icon, :string,
    default: nil,
    doc: "An optional icon to render next to the label."
  )

  attr(:rest, :global)

  def tag_cell(assigns) do
    ~H"""
    <div data-part="cell" data-type="tag" {@rest}>
      <.tag label={@label} icon={@icon} />
    </div>
    """
  end

  attr(:status, :string,
    values: ~w(success error warning disabled attention),
    required: true,
    doc: "The status of the badge"
  )

  attr(:label, :string, default: nil, doc: "The label of the badge")
  attr(:rest, :global)

  def status_badge_cell(assigns) do
    ~H"""
    <div data-part="cell" data-type="status_badge" {@rest}>
      <.status_badge status={@status} label={@label} />
    </div>
    """
  end

  attr(:rest, :global)
  slot(:button, required: true, doc: "The button or buttons to render")

  def button_cell(assigns) do
    ~H"""
    <div data-part="cell" data-type="button">
      <%= for button <- @button do %>
        {render_slot(button)}
      <% end %>
    </div>
    """
  end

  attr(:label, :string, required: true, doc: "The label of the button")

  attr(:variant, :string,
    values: button_variants(),
    default: "primary",
    doc: "Determines the style"
  )

  attr(:underline, :boolean, default: false, doc: "Determines if the button is underlined")

  attr(:rest, :global)

  slot(:icon_left, doc: "Icon displayed on the left of an item")
  slot(:icon_right, doc: "Icon displayed on the right of an item")

  def link_button_cell(assigns) do
    ~H"""
    <div data-part="cell" data-type="link_button" {@rest}>
      <.link_button label={@label} variant={@variant} underline={@underline} size="large">
        <:icon_left>
          {render_slot(@icon_left)}
        </:icon_left>
        <:icon_right>
          {render_slot(@icon_right)}
        </:icon_right>
      </.link_button>
    </div>
    """
  end

  attr(:time, DateTime, required: true, doc: "The time to render.")
  attr(:show_time, :boolean, default: false, doc: "Whether to show the time or date only.")
  attr(:relative, :boolean, default: false, doc: "Whether to show the time relative to now.")
  attr(:rest, :global)

  def time_cell(assigns) do
    ~H"""
    <div data-part="cell" data-type="text" {@rest}>
      <span data-part="label">
        <.time time={@time} show_time={@show_time} relative={@relative} />
      </span>
    </div>
    """
  end

  attr(:icon, :string, default: nil, doc: "Icon to show in the empty state.")
  attr(:title, :string, default: nil, doc: "Title of the empty state.")
  attr(:subtitle, :string, default: nil, doc: "Subtitle of the empty state.")

  slot(:inner_block, doc: "Custom empty state content. Supersedes all attributes.")

  def table_empty_state(assigns) do
    ~H"""
    <div class="noora-table-empty-state">
      <%= if has_slot_content?(@inner_block, assigns) do %>
        {render_slot(@inner_block)}
      <% else %>
        <div :if={@icon} data-part="icon">
          <.icon name={@icon} />
        </div>
        <div :if={@title} data-part="title">
          {@title}
        </div>
        <div :if={@subtitle} data-part="subtitle">
          {@subtitle}
        </div>
      <% end %>
    </div>
    """
  end
end
