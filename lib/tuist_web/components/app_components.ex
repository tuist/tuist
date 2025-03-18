defmodule TuistWeb.AppComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as modals, tables, and
  forms. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The default components use Tailwind CSS, a utility-first CSS framework.
  See the [Tailwind CSS documentation](https://tailwindcss.com) to learn
  how to customize them or feel free to swap in another framework altogether.

  Icons are provided by [heroicons](https://heroicons.com). See `icon/1` for usage.
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS
  use Gettext, backend: TuistWeb.Gettext
  import TuistWeb.Components.IconComponents

  @doc """
  Renders a section header
  """

  attr(:class, :string, default: "")
  attr(:title, :string, required: true)
  attr(:subtitle, :string, default: nil)

  def section_header(assigns) do
    ~H"""
    <div class="section-header">
      <.stack gap="xs">
        <p class="text--large color--text-primary font--semibold">{@title}</p>
        <%= if @subtitle != nil do %>
          <p class="text--small color--text-tertiary font--regular">{@subtitle}</p>
        <% end %>
      </.stack>
    </div>
    """
  end

  @doc """
  Renders a card component
  """

  attr(:class, :string, default: "")
  slot(:inner_block, required: true)

  def card(assigns) do
    ~H"""
    <div class={"card #{@class}"}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Renders a stack component
  """

  attr(:direction, :string, default: "vertical")
  attr(:gap, :string, default: "xs")
  attr(:align, :string, default: nil)
  attr(:class, :string, default: "")
  slot(:inner_block, required: true)

  def stack(assigns) do
    ~H"""
    <div
      class={"stack stack--#{@direction} stack--#{@direction}--#{@gap} #{@class}"}
      style={if not is_nil(@align), do: "align-items: #{@align};"}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Renders a dropdown picker
  """

  attr(:class, :string, default: "")
  attr(:menu_id, :string, required: true)
  attr(:menu_class, :string, default: "")
  slot(:inner_block, required: true)
  slot(:content, required: true)
  slot(:icon, required: false)

  def dropdown_picker(assigns) do
    ~H"""
    <div class={"dropdown #{@class}"}>
      <.legacy_button
        class="dropdown-button"
        variant="secondary"
        size="medium"
        aria-expanded="false"
        phx-click={JS.toggle(to: "##{@menu_id}")}
        phx-window-keydown={JS.hide(to: "##{@menu_id}")}
        phx-key="Escape"
        type="button"
      >
        <:icon_start>
          <%= if @icon != [] do %>
            {render_slot(@icon)}
          <% end %>
        </:icon_start>
        {render_slot(@inner_block)}
        <:icon>
          <%= if @icon == [] do %>
            <.chevron_down_icon />
          <% end %>
        </:icon>
      </.legacy_button>

      <div
        class={"dropdown-menu #{@menu_class}"}
        id={@menu_id}
        hidden
        phx-click-away={JS.hide(to: "##{@menu_id}")}
      >
        {render_slot(@content)}
      </div>
    </div>
    """
  end

  @doc """
  Renders a button.

  ## Examples

      <.legacy_button>Send!</.button>
      <.legacy_button phx-click="go">Send!</.button>
  """
  attr(:variant, :string, default: "primary")
  attr(:size, :string, default: "medium")
  attr(:rest, :global, include: ~w(disabled form name value id))
  attr(:class, :string, default: "")
  attr(:loading, :boolean, default: false)

  slot(:inner_block, required: false)
  slot(:icon_start, doc: "the slot for an icon to present at the start of the button")
  slot(:icon, doc: "the slot for an icon")

  def legacy_button(assigns) do
    ~H"""
    <button
      class={"button--#{@variant} button--#{@size} #{@class} #{if @loading == [], do: "button--icon-only"}"}
      {@rest}
    >
      <%= if @loading do %>
        <span class="loader"></span>
      <% else %>
        {render_slot(@icon_start)}
        <span class={"text--#{case @size do
        "small" -> "small"
        "medium" -> "small"
        "large" -> "medium"
        "extraLarge" -> "medium"
        "extraExtraLarge" -> "large"
      end
      } font--semibold"}>
          {render_slot(@inner_block)}
        </span>
        {render_slot(@icon)}
      <% end %>
    </button>
    """
  end

  @doc """
  Renders a social button
  """

  attr(:rest, :global, include: ~w(disabled form name value))
  slot(:inner_block, required: false)
  slot(:icon, required: true)

  def social_button(assigns) do
    ~H"""
    <button class="social-button" class="auth-form__primary-action">
      <.stack direction="horizontal" gap="lg">
        {render_slot(@icon)}
        <span class="text--medium font--semibold">{render_slot(@inner_block)}</span>
      </.stack>
    </button>
    """
  end

  @doc """
  Renders a button group.

  ## Examples

  <.button_group selected_key="button_1">
    <:button key="button_1">Button 1</:button>
    <:button key="button_2">Button 2</:button>
  </.button_group>
  """
  slot(:button, required: false) do
    attr(:key, :string, required: true)
  end

  attr(:selected_key, :string, required: true)

  def button_group(assigns) do
    ~H"""
    <div class="button-group">
      <%= for button <- @button do %>
        <button class={
          if button.key == @selected_key do
            "button-group__button--selected"
          else
            ""
          end
        }>
          <span class="text--small font--semibold">
            {render_slot(button)}
          </span>
        </button>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders a modal.

  ## Examples

      <.legacy_modal id="confirm-modal">
        This is a modal.
      </.legacy_modal>

  JS commands may be passed to the `:on_cancel` to configure
  the closing/cancel event, for example:

      <.legacy_modal id="confirm" on_cancel={JS.navigate(~p"/posts")}>
        This is another modal.
      </.legacy_modal>

  """
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :on_cancel, JS, default: %JS{}
  slot :inner_block, required: true

  def legacy_modal(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
      class="modal"
    >
      <div id={"#{@id}-bg"} class="modal__background" aria-hidden="true" />
      <div
        class="modal__dialog"
        aria-labelledby={"#{@id}-title"}
        aria-describedby={"#{@id}-description"}
        role="dialog"
        aria-modal="true"
        tabindex="0"
      >
        <.focus_wrap
          id={"#{@id}-container"}
          phx-window-keydown={JS.exec("data-cancel", to: "##{@id}")}
          phx-key="escape"
          phx-click-away={JS.exec("data-cancel", to: "##{@id}")}
          class="modal__dialog__container"
        >
          <button
            phx-click={JS.exec("data-cancel", to: "##{@id}")}
            aria-label={gettext("close")}
            class="modal__dialog__container__close-button button--small button--tertiary button--icon-only"
          >
            <.close_icon />
          </button>
          <div id={"#{@id}-content"} class="modal__dialog__container__content">
            {render_slot(@inner_block)}
          </div>
        </.focus_wrap>
      </div>
    </div>
    """
  end

  attr :kind, :atom,
    values: [:info, :error, :warning, :brand, :brand_subtle, :neutral, :success],
    doc: "the kind of badge"

  attr :title, :string, required: true, doc: "the title of the badge"
  slot :icon, doc: "the slot for an icon"

  def legacy_badge(assigns) do
    ~H"""
    <div class={"badge badge--#{@kind}"}>
      {render_slot(@icon)}
      <span class="text--extraSmall font--medium badge__text">{@title}</span>
    </div>
    """
  end

  attr :kind, :atom, values: [:info, :error], doc: "the kind of badge"
  attr :title, :string, required: true, doc: "the title of the badge"
  attr :message, :string, required: true, doc: "the message of the badge"

  def badge_group(assigns) do
    ~H"""
    <button class={"badge-group badge--#{@kind}"}>
      <.stack class="text--extraSmall font--medium" direction="horizontal" gap="xs">
        <span class="badge__type">{@title}</span>
        <span class="badge__text">{@message}</span>
        <.close_icon />
      </.stack>
    </button>
    """
  end

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      {@rest}
    >
      <.badge_group kind={@kind} title={@title} message={msg} />
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  def flash_group(assigns) do
    ~H"""
    <.stack class="flash-group">
      <.flash kind={:info} title={gettext("Info")} flash={@flash} />
      <.flash kind={:error} title={gettext("Error")} flash={@flash} />
    </.stack>
    """
  end

  @doc """
  Renders a simple form.

  ## Examples

      <.simple_form for={@form} phx-change="validate" phx-submit="save">
        <.input field={@form[:email]} label="Email"/>
        <.input field={@form[:username]} label="Username" />
        <:actions>
          <.button>Save</.button>
        </:actions>
      </.simple_form>
  """
  attr :for, :any, required: true, doc: "the datastructure for the form"
  attr :as, :any, default: nil, doc: "the server side parameter to collect all input under"

  attr :rest, :global,
    include: ~w(autocomplete name rel action enctype method novalidate target multipart),
    doc: "the arbitrary HTML attributes to apply to the form tag"

  slot :inner_block, required: true
  slot :actions, doc: "the slot for form actions, such as a submit button"

  def simple_form(assigns) do
    ~H"""
    <.form :let={f} for={@for} as={@as} {@rest}>
      <div class="mt-10 space-y-8 bg-white">
        {render_slot(@inner_block, f)}
        <div :for={action <- @actions} class="mt-2 flex items-center justify-between gap-6">
          {render_slot(action, f)}
        </div>
      </div>
    </.form>
    """
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information.

  ## Examples

      <.input field={@form[:email]} type="email" />
      <.input name="my-input" errors={["oh no!"]} />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file hidden month number password
               range radio search select tel text textarea time url week)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  slot :inner_block

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(field.errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div phx-feedback-for={@name} class="checkbox-container">
      <label class="checkbox-container__label text--small font--medium color--text-secondary">
        <input type="hidden" name={@name} value="false" />
        <input type="checkbox" id={@id} name={@name} value="true" checked={@checked} {@rest} />
        {@label}
        <%= if @inner_block != [] do %>
          {render_slot(@inner_block)}
        <% end %>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "switch"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div phx-feedback-for={@name}>
      <label class="switch">
        <input type="checkbox" id={@id} name={@name} value="true" checked={@checked} {@rest} />
        <span class="slider"></span>
      </label>
    </div>
    """
  end

  def input(%{type: "radio"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("radio", assigns[:value])
      end)

    ~H"""
    <div phx-feedback-for={@name} class="radio-container">
      <label class="radio-container__label text--small font--medium color--text-secondary">
        <input type="hidden" name={@name} value="false" />
        <input type="radio" id={@id} name={@name} value="true" checked={@checked} {@rest} />
        {@label}
        <%= if @inner_block != [] do %>
          {render_slot(@inner_block)}
        <% end %>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label for={@id}>{@label}</.label>
      <select
        id={@id}
        name={@name}
        class="mt-2 block w-full rounded-md border border-gray-300 bg-white shadow-sm focus:border-zinc-400 focus:ring-0 sm:text-sm"
        multiple={@multiple}
        {@rest}
      >
        <option :if={@prompt} value="">{@prompt}</option>
        {Phoenix.HTML.Form.options_for_select(@options, @value)}
      </select>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label for={@id}>{@label}</.label>
      <textarea
        id={@id}
        name={@name}
        class={[
          "mt-2 block w-full rounded-lg text-zinc-900 focus:ring-0 sm:text-sm sm:leading-6",
          "min-h-[6rem] phx-no-feedback:border-zinc-300 phx-no-feedback:focus:border-zinc-400",
          @errors == [] && "border-zinc-300 focus:border-zinc-400",
          @errors != [] && "border-rose-400 focus:border-rose-400"
        ]}
        {@rest}
      ><%= Phoenix.HTML.Form.normalize_value("textarea", @value) %></textarea>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <.stack gap="sm">
      <.label for={@id}>{@label}</.label>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class={[
          "text--medium",
          @errors != [] && "input--error"
        ]}
        {@rest}
      />
      <p :for={msg <- @errors} class="color--text-error-primary text--small font--regular">
        {msg}
      </p>
    </.stack>
    """
  end

  @doc """
  Renders a label.
  """
  attr :for, :string, default: nil
  slot :inner_block, required: true

  def label(assigns) do
    ~H"""
    <label for={@for} class="text--small font--medium color--text-secondary">
      {render_slot(@inner_block)}
    </label>
    """
  end

  @doc """
  Generates a generic error message.
  """
  slot :inner_block, required: true

  def error(assigns) do
    ~H"""
    <p class="mt-3 flex gap-3 text-sm leading-6 text-rose-600 phx-no-feedback:hidden">
      <.icon name="hero-exclamation-circle-mini" class="mt-0.5 h-5 w-5 flex-none" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  attr :class, :string, default: nil

  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", @class]}>
      <div>
        <h1 class="text-lg font-semibold leading-8 text-zinc-800">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="mt-2 text-sm leading-6 text-zinc-600">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  def pagination(assigns) do
    ~H"""
    <nav class="pagination" aria-label="Pagination">
      <.pagination_link
        has_previous_page={@has_previous_page}
        cursor={@start_cursor}
        uri={@uri}
        type={:prev}
      />
      <.pagination_link has_next_page={@has_next_page} cursor={@end_cursor} uri={@uri} type={:next} />
    </nav>
    """
  end

  attr(:class, :string, default: nil)
  attr(:uri, URI, required: true)
  attr(:type, :atom, required: true)
  attr(:cursor, :string, required: true)
  attr(:has_previous_page, :boolean, default: false)
  attr(:has_next_page, :boolean, default: false)

  defp pagination_link(assigns) do
    {disabled?, uri} =
      case {assigns.type, assigns.cursor, assigns.has_previous_page, assigns.has_next_page} do
        {:next, cursor, _has_previous_page, has_next_page} when has_next_page == true ->
          params =
            URI.decode_query(assigns.uri.query)
            |> Map.put("after", cursor)
            |> Map.delete("before")

          {false, %{assigns.uri | query: URI.encode_query(params)}}

        {:prev, cursor, has_previous_page, _has_next_page} when has_previous_page == true ->
          params =
            URI.decode_query(assigns.uri.query)
            |> Map.delete("after")
            |> Map.put("before", cursor)

          {false, %{assigns.uri | query: URI.encode_query(params)}}

        {_, _, _, _} ->
          {true, nil}
      end

    assigns = assign(assigns, uri: not disabled? && URI.to_string(uri), disabled?: disabled?)

    ~H"""
    <%= if @type == :prev do %>
      <.link navigate={@uri} class="pagination-link">
        <.legacy_button variant="secondary" size="small" disabled={@disabled?}>
          <:icon_start><.arrow_left_icon /></:icon_start>
          {gettext("Previous")}
        </.legacy_button>
      </.link>
    <% else %>
      <.link navigate={@uri} class="pagination-link">
        <.legacy_button variant="secondary" size="small" disabled={@disabled?}>
          <:icon><.arrow_right_icon /></:icon>
          {gettext("Next")}
        </.legacy_button>
      </.link>
    <% end %>
    """
  end

  @doc ~S"""
  Renders a table with generic styling.

  ## Examples

      <.legacy_table id="users" rows={@users}>
        <:col :let={user} label="id"><%= user.id %></:col>
        <:col :let={user} label="username"><%= user.username %></:col>
      </.legacy_table>
  """
  attr(:id, :string, required: true)
  attr(:rows, :list, required: true)
  attr(:row_id, :any, default: nil, doc: "the function for generating the row id")
  attr(:row_click, :any, default: nil, doc: "the function for handling phx-click on each row")
  attr(:empty_state_title, :string, required: true)
  attr(:empty_state_subtitle, :string, default: nil)

  attr(:row_link, :any, default: nil, doc: "the function for generating the row link")

  attr(:class, :string, default: nil)

  attr(
    :row_item,
    :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"
  )

  slot(:col, required: true) do
    attr :label, :string
  end

  slot(:footer, doc: "the slot for a table footer with extra actions, such as pagination")
  slot(:empty_state_icon, doc: "the slot for an icon to present in the empty state")

  def legacy_table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div class={["table-container", @class]}>
      <%= if length(@rows) == 0 do %>
        <.stack gap="xl" class="table-container__empty-state">
          <.featured_icon>
            <%= if @empty_state_icon != [] do %>
              {render_slot(@empty_state_icon)}
            <% else %>
              <.search_icon />
            <% end %>
          </.featured_icon>
          <.stack gap="xs" class="table-container__empty-state__labels">
            <p class="text--medium font--semibold color--text-primary">
              {@empty_state_title}
            </p>
            <p class="text--small font--regular color--text-tertiary">
              {@empty_state_subtitle}
            </p>
          </.stack>
        </.stack>
      <% else %>
        <table>
          <thead>
            <tr>
              <th :for={col <- @col}>{col[:label]}</th>
            </tr>
          </thead>
          <tbody id={@id} phx-update={match?(%Phoenix.LiveView.LiveStream{}, @rows) && "stream"}>
            <tr
              :for={row <- @rows}
              id={@row_id && @row_id.(row)}
              class={[(not is_nil(@row_link) or @row_click) && "clickable"]}
            >
              <td
                :for={col <- @col}
                phx-click={@row_click && @row_click.(row)}
                class={["text--small"]}
              >
                <%= if not is_nil(@row_link) do %>
                  <.link href={@row_link.(row)} class="table-container__data-container">
                    {render_slot(col, @row_item.(row))}
                  </.link>
                <% else %>
                  <div class="table-container__data-container">
                    {render_slot(col, @row_item.(row))}
                  </div>
                <% end %>
              </td>
            </tr>
          </tbody>
        </table>
        <%= if @footer != [] do %>
          <div class="table-container__footer">
            {render_slot(@footer)}
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title"><%= @post.title %></:item>
        <:item title="Views"><%= @post.views %></:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <div class="mt-14">
      <dl class="-my-4 divide-y divide-zinc-100">
        <div :for={item <- @item} class="flex gap-4 py-4 text-sm leading-6 sm:gap-8">
          <dt class="w-1/4 flex-none text-zinc-500">{item.title}</dt>
          <dd class="text-zinc-700">{render_slot(item)}</dd>
        </div>
      </dl>
    </div>
    """
  end

  @doc """
  Renders a back navigation link.

  ## Examples

      <.back navigate={~p"/posts"}>Back to posts</.back>
  """
  attr :navigate, :any, required: true
  slot :inner_block, required: true

  def back(assigns) do
    ~H"""
    <div class="mt-16">
      <.link
        navigate={@navigate}
        class="text-sm font-semibold leading-6 text-zinc-900 hover:text-zinc-700"
      >
        <.icon name="hero-arrow-left-solid" class="h-3 w-3" />
        {render_slot(@inner_block)}
      </.link>
    </div>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in your `assets/tailwind.config.js`.

  ## Examples

      <.icon name="hero-x-mark-solid" />
      <.icon name="hero-arrow-path" class="ml-1 w-3 h-3 animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :string, default: nil

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      transition:
        {"transition-all transform ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all transform ease-in duration-200",
         "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  def show_modal(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.show(to: "##{id}")
    |> JS.show(
      to: "##{id}-bg",
      transition: {"transition-all transform ease-out duration-300", "opacity-0", "opacity-100"}
    )
    |> show("##{id}-container")
    |> JS.add_class("overflow-hidden", to: "body")
    |> JS.focus_first(to: "##{id}-content")
  end

  def hide_modal(js \\ %JS{}, id) do
    js
    |> JS.hide(
      to: "##{id}-bg",
      transition: {"transition-all transform ease-in duration-200", "opacity-100", "opacity-0"}
    )
    |> hide("##{id}-container")
    |> JS.hide(to: "##{id}", transition: {"block", "block", "hidden"})
    |> JS.remove_class("overflow-hidden", to: "body")
    |> JS.pop_focus()
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(TuistWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(TuistWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end

  attr :class, :string, default: ""

  def decorative_background(assigns) do
    ~H"""
    <svg
      width="768"
      height="520"
      viewBox="0 0 768 520"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      class={@class}
    >
      <mask
        id="mask0_5022_371856"
        style="mask-type:alpha"
        maskUnits="userSpaceOnUse"
        x="0"
        y="-248"
        width="768"
        height="768"
      >
        <rect
          width="768"
          height="768"
          transform="translate(0 -248)"
          fill="url(#paint0_radial_5022_371856)"
        />
      </mask>
      <g mask="url(#mask0_5022_371856)">
        <g clip-path="url(#clip0_5022_371856)">
          <g clip-path="url(#clip1_5022_371856)">
            <line x1="0.5" y1="-248" x2="0.5" y2="520" stroke="#1F242F" />
            <line x1="48.5" y1="-248" x2="48.5" y2="520" stroke="#1F242F" />
            <line x1="96.5" y1="-248" x2="96.5" y2="520" stroke="#1F242F" />
            <line x1="144.5" y1="-248" x2="144.5" y2="520" stroke="#1F242F" />
            <line x1="192.5" y1="-248" x2="192.5" y2="520" stroke="#1F242F" />
            <line x1="240.5" y1="-248" x2="240.5" y2="520" stroke="#1F242F" />
            <line x1="288.5" y1="-248" x2="288.5" y2="520" stroke="#1F242F" />
            <line x1="336.5" y1="-248" x2="336.5" y2="520" stroke="#1F242F" />
            <line x1="384.5" y1="-248" x2="384.5" y2="520" stroke="#1F242F" />
            <line x1="432.5" y1="-248" x2="432.5" y2="520" stroke="#1F242F" />
            <line x1="480.5" y1="-248" x2="480.5" y2="520" stroke="#1F242F" />
            <line x1="528.5" y1="-248" x2="528.5" y2="520" stroke="#1F242F" />
            <line x1="576.5" y1="-248" x2="576.5" y2="520" stroke="#1F242F" />
            <line x1="624.5" y1="-248" x2="624.5" y2="520" stroke="#1F242F" />
            <line x1="672.5" y1="-248" x2="672.5" y2="520" stroke="#1F242F" />
            <line x1="720.5" y1="-248" x2="720.5" y2="520" stroke="#1F242F" />
          </g>
          <rect x="0.5" y="-247.5" width="767" height="767" stroke="#1F242F" />
          <g clip-path="url(#clip2_5022_371856)">
            <line y1="39.5" x2="768" y2="39.5" stroke="#1F242F" />
            <line y1="87.5" x2="768" y2="87.5" stroke="#1F242F" />
            <line y1="135.5" x2="768" y2="135.5" stroke="#1F242F" />
            <line y1="183.5" x2="768" y2="183.5" stroke="#1F242F" />
            <line y1="231.5" x2="768" y2="231.5" stroke="#1F242F" />
            <line y1="279.5" x2="768" y2="279.5" stroke="#1F242F" />
            <line y1="327.5" x2="768" y2="327.5" stroke="#1F242F" />
            <line y1="375.5" x2="768" y2="375.5" stroke="#1F242F" />
            <line y1="423.5" x2="768" y2="423.5" stroke="#1F242F" />
            <line y1="471.5" x2="768" y2="471.5" stroke="#1F242F" />
            <line y1="519.5" x2="768" y2="519.5" stroke="#1F242F" />
          </g>
          <rect x="0.5" y="-247.5" width="767" height="767" stroke="#1F242F" />
        </g>
      </g>
      <defs>
        <radialGradient
          id="paint0_radial_5022_371856"
          cx="0"
          cy="0"
          r="1"
          gradientUnits="userSpaceOnUse"
          gradientTransform="translate(384 384) rotate(90) scale(384 384)"
        >
          <stop />
          <stop offset="1" stop-opacity="0" />
        </radialGradient>
        <clipPath id="clip0_5022_371856">
          <rect width="768" height="768" fill="white" transform="translate(0 -248)" />
        </clipPath>
        <clipPath id="clip1_5022_371856">
          <rect y="-248" width="768" height="768" fill="white" />
        </clipPath>
        <clipPath id="clip2_5022_371856">
          <rect y="-248" width="768" height="768" fill="white" />
        </clipPath>
      </defs>
    </svg>
    """
  end
end
