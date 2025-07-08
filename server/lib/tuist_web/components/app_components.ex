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
  use Gettext, backend: TuistWeb.Gettext
  use Noora

  import TuistWeb.Components.EmptyStateBackground
  import TuistWeb.Components.TrendBadge

  alias Phoenix.LiveView.JS
  alias TuistWeb.Utilities.Query

  attr :id, :string, required: true, doc: "The id of the widget."
  attr :title, :string, required: true, doc: "The title of the widget."

  attr :legend_color, :string,
    values: ~w(primary secondary destructive),
    required: false,
    doc: "The color of the legend. The legend is hidden if the value is `nil`."

  attr :description, :string,
    required: false,
    doc: "The description of the widget value.",
    default: nil

  attr :value, :string, required: true, doc: "The value of the widget."

  attr :trend_value, :integer,
    required: false,
    default: nil,
    doc: "The trend value of the widget."

  attr :trend_label, :string, required: false, doc: "The trend label of the widget."

  attr :trend_inverse, :boolean,
    default: false,
    doc: "Set this to true when smaller number means the trend is positive."

  attr :patch, :string, default: nil, doc: "Patches the current LiveView"

  attr :replace, :boolean,
    default: false,
    doc: "Whether to replace the current history entry when patching."

  attr :selected, :boolean,
    default: false,
    doc: "Whether the widget is selected. Only applicable when patch is not nil."

  attr :empty, :boolean, default: false, doc: "Whether the widget is empty"

  def widget(assigns) do
    ~H"""
    <%= if @empty do %>
      <.card_section class="tuist-widget" id={@id}>
        <div data-part="background">
          <.empty_state_background />
        </div>
        <div data-part="header">
          <span data-part="title">{@title}</span>
        </div>
        <span data-part="empty-label">
          {gettext("No data yet")}
        </span>
      </.card_section>
    <% else %>
      <.link
        :if={@patch}
        patch={@patch}
        replace={@replace}
        data-selected={@selected}
        class="tuist-widget-link"
      >
        <.static_widget {assigns} />
      </.link>
      <.static_widget :if={!@patch} {assigns} />
    <% end %>
    """
  end

  defp static_widget(assigns) do
    ~H"""
    <.card_section class="tuist-widget" id={@id}>
      <div data-part="header">
        <div
          :if={not is_nil(Map.get(assigns, :legend_color))}
          data-color={@legend_color}
          data-part="legend"
        >
        </div>
        <span data-part="title">{@title}</span>
        <.tooltip
          :if={@description}
          id={@id <> "-tooltip"}
          title={@title}
          description={@description}
          size="large"
        >
          <:trigger :let={attrs}>
            <span {attrs} data-part="tooltip-icon">
              <.alert_circle />
            </span>
          </:trigger>
        </.tooltip>
      </div>
      <span data-part="value">{@value}</span>
      <div :if={@trend_value} data-part="trend">
        <.trend_badge trend_value={@trend_value} trend_inverse={@trend_inverse} />
        <span data-part="label">{@trend_label}</span>
      </div>
    </.card_section>
    """
  end

  attr :title, :string, required: true, doc: "The title of the legend."
  attr :value, :string, doc: "The value associated with the legend type.", default: nil

  attr :style, :string,
    required: false,
    default: "primary",
    values: ~w(primary secondary destructive),
    doc: "The style of the legend."

  def legend(assigns) do
    ~H"""
    <div class="tuist-legend" data-style={@style}>
      <div data-part="header">
        <div data-part="indicator"></div>
        <span data-part="title">{@title}</span>
      </div>
      <span :if={not is_nil(@value)} data-part="value">{@value}</span>
    </div>
    """
  end

  def pagination(assigns) do
    ~H"""
    <div class="tuist-pagination">
      <.button
        variant="secondary"
        label={gettext("Prev")}
        disabled={not @has_previous_page}
        patch={"?#{@uri.query |> Query.drop("after") |> Query.put("before", @start_cursor)}"}
      >
        <:icon_left><.chevron_left /></:icon_left>
      </.button>
      <.button
        variant="secondary"
        disabled={not @has_next_page}
        label={gettext("Next")}
        patch={"?#{@uri.query |> Query.drop("before") |> Query.put("after", @end_cursor)}"}
      >
        <:icon_right><.chevron_right /></:icon_right>
      </.button>
    </div>
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      transition:
        {"transition-all transform ease-out duration-300", "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all transform ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
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
end
