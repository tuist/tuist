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

  Expansion is handled entirely client-side: clicking a row toggles it without a server
  round trip, so the reveal animation starts instantly. The expanded content is always
  rendered (collapsed to zero height), and `expanded_rows` only sets which rows start out
  expanded. No `handle_event` is needed. Note that a LiveView re-render of the table (for
  example sorting or searching) resets rows to that initial state.

  ```
  <.table
    id="expandable-table"
    rows={@tasks}
    row_key={fn task -> task.key end}
    row_expandable={fn task -> not Enum.empty?(task.details) end}
    expanded_rows={[]}
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
  """

  use Phoenix.Component

  import Noora.Badge
  import Noora.Button
  import Noora.Icon
  import Noora.Tag
  import Noora.Time
  import Noora.Utils

  alias Phoenix.LiveView.JS

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

  attr(:expand_label, :string,
    default: "Toggle row details",
    doc: "Accessible label for the disclosure button that expands/collapses a row."
  )

  slot(:empty_state, required: false)

  slot :col, required: true do
    attr(:label, :string, required: false, doc: "The label of the column")
    attr(:icon, :string, doc: "An icon to render next to the label")
    attr(:patch, :string, doc: "A patch to apply to the column")

    attr(:sort_order, :any,
      doc:
        ~s(When set to "asc" or "desc", renders a sort-direction arrow that morphs between the two directions as the value changes. Mirror your sort-state gating, e.g. `sort_order={@sort_by == "duration" && @sort_order}`.)
    )
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
    <div id={@id} class="noora-table" phx-hook="NooraTable">
      <div data-part="scroll-container">
        <table>
          <thead>
            <tr>
              <th :for={{col, col_index} <- Enum.with_index(@col)}>
                <%= if col[:patch] do %>
                  <.link patch={col[:patch]} data-part="sort-link">
                    <span>{col[:label]}</span>
                    <span :if={col[:icon]} data-part="icon"><.icon name={col[:icon]} /></span>
                    <.sort_indicator
                      :if={col[:sort_order]}
                      id={"#{@id}-sort-#{col_index}"}
                      order={col[:sort_order]}
                    />
                  </.link>
                <% else %>
                  <span>{col[:label]}</span>
                  <span :if={col[:icon]} data-part="icon"><.icon name={col[:icon]} /></span>
                  <.sort_indicator
                    :if={col[:sort_order]}
                    id={"#{@id}-sort-#{col_index}"}
                    order={col[:sort_order]}
                  />
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

              <%!-- Expansion is presentational, toggled client-side via the disclosure button
              in the first cell — not a click handler on the row. A passive row keeps text
              selectable (so cache keys can be copied without collapsing), lets controls inside
              the row work without double-firing, and routes keyboard users through a real
              focusable button. The button flips `data-state` on this row; the expanded sibling
              row, the row background, and the chevron all derive from that attribute. --%>
              <tr
                id={row_key}
                {if is_expandable,
               do: %{},
               else: if(@row_click, do: @row_click.(row) || %{}, else: %{})}
                data-expandable={is_expandable}
                data-state={is_expandable && if(is_expanded, do: "expanded", else: "collapsed")}
              >
                <td
                  :for={{col, index} <- Enum.with_index(@col)}
                  data-selectable={
                    !is_expandable &&
                      (not is_nil(@row_navigate) or
                         (not is_nil(@row_click) && not is_nil(@row_click.(row))))
                  }
                >
                  <%= cond do %>
                    <% is_expandable && index == 0 -> %>
                      <div data-part="expand-cell">
                        <button
                          type="button"
                          data-part="expand-toggle"
                          aria-expanded={to_string(is_expanded)}
                          aria-controls={"#{row_key}-expanded"}
                          aria-label={@expand_label}
                          phx-click={
                            JS.toggle_attribute({"data-state", "expanded", "collapsed"},
                              to: "##{row_key}"
                            )
                            |> JS.toggle_attribute({"aria-expanded", "true", "false"})
                          }
                        >
                          <.icon
                            id={"#{row_key}-expand-chevron"}
                            name="chevron_right"
                            active_name="chevron_down"
                            transition="crossfade_rotate"
                            watch="tr[data-expandable]"
                            active_state="expanded"
                          />
                        </button>
                        {render_slot(col, row)}
                      </div>
                    <% @row_navigate && !is_expandable && index == 0 -> %>
                      <%!-- Whole-row navigation, built from real anchors so browsers keep their
                      native link affordances (hover URL preview, Safari/Firefox link previews,
                      Cmd/middle-click to open in a new tab) with no JS. The first cell carries the
                      one focusable, announced link wrapping its content, stretched over its own
                      cell by a `::after` overlay (see table.css); every other cell gets a decorative
                      empty overlay anchor below. The row reads as one link — one tab stop, announced
                      once. --%>
                      <.link navigate={@row_navigate.(row)} data-part="row-link">
                        {render_slot(col, row)}
                      </.link>
                    <% @row_navigate && !is_expandable -> %>
                      <%!-- Decorative per-cell overlay: an empty real anchor stretched over the
                      cell (`<td>` IS a valid containing block in every engine — only `<tr>` is not,
                      which is why a single row-spanning overlay can't work in WebKit). It widens the
                      pointer/hover hit area to the whole row while staying out of the focus order and
                      a11y tree, so only the first cell's link is announced. --%>
                      {render_slot(col, row)}
                      <.link
                        navigate={@row_navigate.(row)}
                        data-part="row-link-overlay"
                        tabindex="-1"
                        aria-hidden="true"
                      >
                      </.link>
                    <% true -> %>
                      {render_slot(col, row)}
                  <% end %>
                </td>
              </tr>

              <%!-- Always rendered (collapsed to zero height) rather than inserted/removed on
              toggle: the reveal is a plain CSS transition keyed off the preceding row's
              `data-state`, so there's no mount cost before the animation can start and no
              removal timer racing the collapse. --%>
              <tr
                :if={is_expandable && @expanded_content != []}
                data-part="expanded-row"
                id={"#{row_key}-expanded"}
              >
                <td colspan={length(@col)} data-part="expanded-content">
                  <div data-part="expand-wrapper">
                    <div data-part="expand-wrapper-content">
                      {render_slot(@expanded_content, row)}
                    </div>
                  </div>
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
      <div data-part="scrollbar" aria-hidden="true">
        <div data-part="scrollbar-content"></div>
      </div>
      <div data-part="overlay-scrollbar" aria-hidden="true">
        <div data-part="overlay-thumb"></div>
      </div>
    </div>
    """
  end

  attr(:id, :string, required: true, doc: "A unique identifier for the morphing icon")
  attr(:order, :string, required: true, doc: ~s(The current sort order: "asc" or "desc"))

  # A sort-direction arrow that morphs between descending (down) and ascending (up) as `order`
  # changes. The `order` is mirrored onto the wrapping `data-part="icon"` element as `data-state`,
  # which the icon's morph hook watches.
  defp sort_indicator(assigns) do
    ~H"""
    <span data-part="icon" data-state={@order}>
      <.icon
        id={@id}
        name="square_rounded_arrow_down"
        active_name="square_rounded_arrow_up"
        transition="morph"
        watch="[data-part='icon']"
        active_state="asc"
      />
    </span>
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

  attr(:truncate, :boolean,
    default: true,
    doc:
      "Cap the cell to a single line per row and clip overflow with an ellipsis, instead of letting free-form content (e.g. a command with many target arguments) widen the column unbounded. On by default; pass `truncate={false}` to opt out."
  )

  attr(:rest, :global)

  slot(:image,
    required: false,
    doc: "An optional image to render next to the label. Takes precedence over `icon`."
  )

  def text_and_description_cell(assigns) do
    ~H"""
    <div data-part="cell" data-type="text_and_description" data-truncate={@truncate} {@rest}>
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
    values: ~w(success error warning disabled expired attention in_progress),
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
