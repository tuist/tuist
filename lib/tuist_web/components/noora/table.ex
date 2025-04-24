defmodule TuistWeb.Noora.Table do
  @moduledoc """
  Noora's table component.

  The table component is used to display data in a tabular format. It supports various types of cells, such as text, badges, and buttons.

  ## Usage

  The component expects its content to be passed as a list of rows or a LiveView stream as the `rows` attribute. Each row is a map with its
  values.
  Columns are defined using the `col` slot, which takes a label and an optional icon. Inside the columns, a large number of different cells
  are supported.

  ## Example

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
  """

  use Phoenix.Component

  import TuistWeb.Noora.Badge
  import TuistWeb.Noora.Button
  import TuistWeb.Noora.Icon
  import TuistWeb.Noora.Tag
  import TuistWeb.Noora.Time
  import TuistWeb.Noora.Utils

  attr :id, :string, required: true, doc: "A uniqie identifier for the table"

  attr :rows, :list, required: true, doc: "The table content"

  attr :row_key, :fun,
    default: nil,
    doc:
      "A function to generate the row key. Required when using a LiveView stream. If using streams and not provided, defaults to the `id` key of the stream."

  attr :row_navigate, :fun,
    default: nil,
    doc: "A function to generate the link to navigate to when clicking on a row."

  slot :empty_state, required: false

  slot :col, required: true do
    attr :label, :string, required: false, doc: "The label of the column"
    attr :icon, :string, doc: "An icon to render next to the label"
    attr :patch, :string, doc: "A patch to apply to the column"
  end

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns,
          row_key: assigns.row_key || fn {id, _item} -> id end
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
          <tr :for={row <- @rows} id={@row_key && @row_key.(row)}>
            <td :for={col <- @col} data-selectable={not is_nil(@row_navigate)}>
              <%= if @row_navigate do %>
                <.link navigate={@row_navigate.(row)} data-part="link">
                  {render_slot(col, row)}
                </.link>
              <% else %>
                {render_slot(col, row)}
              <% end %>
            </td>
          </tr>
          <tr :if={has_slot_content?(@empty_state, assigns) and Enum.empty?(@rows)}>
            <td colspan={length(@col)}>
              {render_slot(@empty_state)}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr :label, :string, default: nil, doc: "The label of the cell"

  attr :icon, :string,
    default: nil,
    doc: "An optional icon to render next to the label. Mutually exclusive with `image`."

  attr :sublabel, :string, default: nil, doc: "An optional sublabel"

  attr :rest, :global

  slot :image,
    required: false,
    doc: "An optional image to render next to the label. Mutually exclusive with `icon`. Takes precedence over `icon`."

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

  attr :label, :string, default: nil, doc: "The label of the cell"

  attr :icon, :string,
    default: nil,
    doc: "An optional icon to render next to the label. Mutually exclusive with `image`."

  attr :description, :string, default: nil, doc: "The description of the cell"
  attr :secondary_description, :string, default: nil, doc: "The secondary description of the cell"
  attr :rest, :global

  slot :image,
    required: false,
    doc: "An optional image to render next to the label. Takes precedence over `icon`."

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

  attr :label, :string, default: nil, doc: "The label of the badge"

  attr :icon, :string,
    default: nil,
    doc: "An optional icon to render next to the label."

  attr :style, :string,
    values: ~w(fill light-fill),
    default: "fill",
    doc: "The style of the badge"

  attr :color, :string,
    values: ~w(neutral destructive warning attention success information focus primary secondary),
    default: "neutral",
    doc: "The color of the badge"

  attr :rest, :global

  def badge_cell(assigns) do
    ~H"""
    <div data-part="cell" data-type="badge" {@rest}>
      <.badge style={@style} color={@color} size="large" label={@label}>
        <:icon>
          <.icon :if={@icon} name={@icon} />
        </:icon>
      </.badge>
    </div>
    """
  end

  attr :label, :string, default: nil, doc: "The label of the badge"

  attr :icon, :string,
    default: nil,
    doc: "An optional icon to render next to the label."

  attr :rest, :global

  def tag_cell(assigns) do
    ~H"""
    <div data-part="cell" data-type="tag" {@rest}>
      <.tag label={@label} icon={@icon} />
    </div>
    """
  end

  attr :status, :string,
    values: ~w(success error warning disabled),
    required: true,
    doc: "The status of the badge"

  attr :label, :string, default: nil, doc: "The label of the badge"
  attr :rest, :global

  def status_badge_cell(assigns) do
    ~H"""
    <div data-part="cell" data-type="status_badge" {@rest}>
      <.status_badge status={@status} label={@label} />
    </div>
    """
  end

  attr :rest, :global
  slot :button, required: true, doc: "The button or buttons to render"

  def button_cell(assigns) do
    ~H"""
    <div data-part="cell" data-type="button">
      <%= for button <- @button do %>
        {render_slot(button)}
      <% end %>
    </div>
    """
  end

  attr :label, :string, required: true, doc: "The label of the button"

  attr :variant, :string,
    values: button_variants(),
    default: "primary",
    doc: "Determines the style"

  attr :underline, :boolean, default: false, doc: "Determines if the button is underlined"

  attr :rest, :global

  slot :icon_left, doc: "Icon displayed on the left of an item"
  slot :icon_right, doc: "Icon displayed on the right of an item"

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

  attr :time, DateTime, required: true, doc: "The time to render."
  attr :show_time, :boolean, default: false, doc: "Whether to show the time or date only."
  attr :relative, :boolean, default: false, doc: "Whether to show the time relative to now."
  attr :rest, :global

  def time_cell(assigns) do
    ~H"""
    <div data-part="cell" data-type="text" {@rest}>
      <span data-part="label">
        <.time time={@time} show_time={@show_time} relative={@relative} />
      </span>
    </div>
    """
  end

  attr :icon, :string, default: nil, doc: "Icon to show in the empty state."
  attr :title, :string, required: true, doc: "Title of the empty state."
  attr :subtitle, :string, default: nil, doc: "Subtitle of the empty state."

  slot :inner_block, doc: "Custom empty state content. Supersedes all attributes."

  def table_empty_state(assigns) do
    ~H"""
    <div class="noora-table-empty-state">
      <%= if has_slot_content?(@inner_block, assigns) do %>
        {render_slot(@inner_block)}
      <% else %>
        <div :if={@icon} data-part="icon">
          <.icon name={@icon} />
        </div>
        <div data-part="title">
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
