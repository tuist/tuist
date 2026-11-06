defmodule Noora.Menu do
  @moduledoc """
  A menu of actions or links that opens from a trigger.

  ```elixir
  <.menu id="project-actions" label="Actions">
    <.menu_item value="rename" label="Rename">
      <:icon><.pencil /></:icon>
    </.menu_item>
    <.menu_separator />
    <.menu_item value="delete" label="Delete project" variant="destructive" />
  </.menu>
  ```

  The menu opens from a button with a `label`, from a dots button for
  overflow actions (`trigger="dots"`), or from the chevron of a split button
  whose label runs a main action (`trigger="split"`). Items look and behave
  the same in every menu. Items take an optional 16px `icon` or 20px
  `image` (an avatar or a logo), a `sublabel`, a `description` on a second
  line, and trailing `extra` content such as a shortcut or a badge.
  """
  use Phoenix.Component

  import Noora.CheckboxControl
  import Noora.Icon, except: [menu: 1]
  import Noora.LineDivider
  import Noora.MiddleTruncate
  import Noora.Utils

  attr(:id, :string, required: true, doc: "Unique identifier for the menu")

  attr(:label, :string,
    required: true,
    doc: "The button's label. With the dots trigger, it isn't shown but names the button for screen readers."
  )

  attr(:trigger, :string,
    values: ~w(label dots split),
    default: "label",
    doc:
      "What opens the menu: a button with the label, a square dots button for overflow actions, or the chevron of a split button whose label runs `on_action`"
  )

  attr(:on_action, :any,
    default: nil,
    doc: "With the split trigger, the event or `Phoenix.LiveView.JS` command the label button runs"
  )

  attr(:placement, :string,
    values: ~w(bottom-start bottom bottom-end top-start top top-end left-start left left-end right-start right right-end),
    default: "bottom-start",
    doc: "Where the menu opens relative to its trigger. It flips when there isn't room."
  )

  attr(:disabled, :boolean,
    default: false,
    doc: "Whether the trigger is disabled. A menu without items is disabled too, except a split button's main action."
  )

  attr(:close_on_select, :boolean,
    default: true,
    doc: "Whether choosing an item closes the menu. Checkbox items always keep it open."
  )

  attr(:on_select, :string,
    default: nil,
    doc:
      "Event pushed when an item is chosen, with its `value`, and for a checkbox item the `checked` state it toggled to"
  )

  attr(:on_open_change, :string, default: nil, doc: "Event pushed when the menu opens or closes")

  attr(:rest, :global, doc: "Additional HTML attributes")

  slot(:inner_block, doc: "The menu's items and separators")

  def menu(assigns) do
    assigns = assign(assigns, :empty, not has_slot_content?(assigns.inner_block, assigns))

    ~H"""
    <.portal
      :if={@trigger != "dots"}
      id={@id <> "-trigger-portal"}
      target={"#" <> @id <> "-trigger-target"}
    >
      <span data-part="label"><.middle_truncate value={@label} /></span>
    </.portal>
    <.portal id={@id <> "-content-portal"} target={"#" <> @id <> "-content-target"}>
      {render_slot(@inner_block)}
    </.portal>
    <div
      id={@id}
      class="noora-menu"
      phx-hook="NooraMenu"
      phx-update="ignore"
      data-trigger={if @trigger == "split", do: "split", else: "dropdown"}
      data-size="large"
      data-loop-focus
      data-typeahead
      data-close-on-select={to_string(@close_on_select)}
      data-positioning-placement={@placement}
      data-positioning-offset-main-axis={8}
      data-positioning-anchor={if @trigger == "split", do: "root"}
      data-on-select={@on_select}
      data-on-open-change={@on_open_change}
      data-disabled={@disabled}
      data-empty={@empty}
      {@rest}
    >
      <button
        :if={@trigger == "label"}
        data-part="trigger"
        type="button"
        disabled={@disabled or @empty}
      >
        <div data-part="label-wrapper">
          <span id={@id <> "-trigger-target"} data-part="trigger-content"></span>
        </div>
        <div data-part="indicator">
          <div>
            <.icon
              id={@id <> "-indicator"}
              name="chevron_down"
              active_name="chevron_up"
              transition="crossfade_rotate"
              active_state="open"
            />
          </div>
        </div>
      </button>
      <button
        :if={@trigger == "split"}
        data-part="main-button"
        type="button"
        disabled={@disabled}
        phx-click={@on_action}
      >
        <span data-part="label-wrapper">
          <span id={@id <> "-trigger-target"} data-part="trigger-content"></span>
        </span>
      </button>
      <button
        :if={@trigger == "split"}
        data-part="trigger"
        type="button"
        disabled={@disabled or @empty}
        aria-label={"#{@label} options"}
      >
        <div data-part="indicator">
          <.icon
            id={@id <> "-indicator"}
            name="chevron_down"
            active_name="chevron_up"
            transition="crossfade_rotate"
            active_state="open"
          />
        </div>
      </button>
      <button
        :if={@trigger == "dots"}
        data-part="trigger"
        data-icon-only
        type="button"
        disabled={@disabled or @empty}
        aria-label={@label}
      >
        <div data-part="icon"><.dots_vertical /></div>
      </button>
      <div data-part="positioner">
        <div class="noora-menu-panel" data-part="content">
          <div id={@id <> "-content-target"} data-part="items"></div>
        </div>
      </div>
    </div>
    """
  end

  attr(:value, :string,
    required: true,
    doc: "Identifies the item, so it must be unique within the menu; sent with the menu's `on_select` event"
  )

  attr(:label, :string, required: true, doc: "The item's text")
  attr(:sublabel, :string, default: nil, doc: "Secondary text shown in parentheses after the label")
  attr(:description, :string, default: nil, doc: "A second line under the label. The item grows to fit it.")

  attr(:truncate, :string,
    values: ~w(end middle),
    default: "end",
    doc:
      "How a label too long for the menu is shortened. `end` suits actions; `middle` keeps both ends of identifiers such as schemes, branches, and project names."
  )

  attr(:variant, :string,
    values: ~w(default destructive),
    default: "default",
    doc: "`destructive` colors the item red, for actions such as deleting. Put these last, after a separator."
  )

  attr(:disabled, :boolean,
    default: false,
    doc: "Whether the item is unavailable. Keyboard navigation skips it."
  )

  attr(:checked, :boolean,
    default: nil,
    doc:
      "Makes the item a checkbox, checked or not, for choosing several options. Choosing it toggles it in place, keeps the menu open, and sends `on_select` with the new `checked`. Rendering it with a different `checked` overrides the toggle."
  )

  attr(:selected, :boolean,
    default: false,
    doc: "Shows a check at the end of the item, for the current choice"
  )

  attr(:href, :string, default: nil, doc: "Navigates to this URL with a full page load")
  attr(:navigate, :string, default: nil, doc: "Navigates to this LiveView")
  attr(:patch, :string, default: nil, doc: "Patches the current LiveView")

  attr(:on_click, :any,
    default: nil,
    doc:
      "Event or `JS` command run when the item is chosen. It runs alongside the menu's `on_select`, so handle a choice in one of them."
  )

  attr(:rest, :global, include: ~w(target rel download), doc: "Additional HTML attributes")

  slot(:icon, doc: "A 16px icon before the label")
  slot(:image, doc: "A 20px image before the label, such as an avatar or a logo")
  slot(:extra, doc: "Trailing content before the check, such as a shortcut key or a badge")

  def menu_item(assigns) do
    assigns = assign(assigns, :link?, not (is_nil(assigns.href) and is_nil(assigns.navigate) and is_nil(assigns.patch)))

    ~H"""
    <.link
      :if={@link? and not @disabled}
      class="noora-menu-item"
      data-part="item"
      data-value={@value}
      data-label={@label}
      data-variant={@variant}
      data-selected={@selected}
      data-checkbox={not is_nil(@checked)}
      data-checked={if not is_nil(@checked), do: to_string(@checked)}
      href={@href}
      navigate={@navigate}
      patch={@patch}
      phx-click={@on_click}
      {@rest}
    >
      <.menu_item_content {assigns} />
    </.link>
    <div
      :if={not @link? or @disabled}
      class="noora-menu-item"
      data-part="item"
      data-value={@value}
      data-label={@label}
      data-variant={@variant}
      data-selected={@selected}
      data-checkbox={not is_nil(@checked)}
      data-checked={if not is_nil(@checked), do: to_string(@checked)}
      data-disabled={@disabled}
      phx-click={if not @disabled, do: @on_click}
      {@rest}
    >
      <.menu_item_content {assigns} />
    </div>
    """
  end

  defp menu_item_content(assigns) do
    assigns = assign(assigns, :label_title, if(String.length(assigns.label) > 24, do: assigns.label))

    ~H"""
    <div :if={not is_nil(@checked)} data-part="checkbox">
      <.checkbox_control checked={@checked} />
    </div>
    <div :if={has_slot_content?(@image, assigns)} data-part="image">{render_slot(@image)}</div>
    <div :if={has_slot_content?(@icon, assigns)} data-part="icon">{render_slot(@icon)}</div>
    <div data-part="body">
      <div data-part="text">
        <span :if={@truncate == "end"} data-part="label" title={@label_title}>{@label}</span>
        <span :if={@truncate == "middle"} data-part="label" data-truncate="middle">
          <.middle_truncate value={@label} />
        </span>
        <span :if={@sublabel} data-part="sublabel">({@sublabel})</span>
      </div>
      <span :if={@description} data-part="description">{@description}</span>
    </div>
    <div :if={has_slot_content?(@extra, assigns)} data-part="extra">{render_slot(@extra)}</div>
    <div :if={@selected} data-part="check"><.check /></div>
    """
  end

  attr(:rest, :global)

  def menu_separator(assigns) do
    ~H"""
    <.line_divider data-part="separator" role="separator" {@rest} />
    """
  end
end
