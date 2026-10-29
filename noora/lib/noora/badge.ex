defmodule Noora.Badge do
  @moduledoc """
  Renders a customizable badge component with various styles, colors, sizes, and optional icons or status indicators.
  """
  use Phoenix.Component

  import Noora.Icon
  import Noora.Utils

  @badge_contract_path Path.expand("../../components/badge.json", __DIR__)
  @external_resource @badge_contract_path
  @badge_contract @badge_contract_path |> File.read!() |> Jason.decode!()
  @badge_attributes Map.new(@badge_contract["attributes"], &{&1["name"], &1})
  @appearance_contract Map.fetch!(@badge_attributes, "appearance")
  @color_contract Map.fetch!(@badge_attributes, "color")
  @size_contract Map.fetch!(@badge_attributes, "size")
  @disabled_contract Map.fetch!(@badge_attributes, "disabled")
  @dot_contract Map.fetch!(@badge_attributes, "dot")
  @icon_only_contract Map.fetch!(@badge_attributes, "icon-only")
  @label_contract Map.fetch!(@badge_attributes, "label")
  @badge_class @badge_contract["className"]

  def badge_appearances, do: @appearance_contract["values"]
  def badge_colors, do: @color_contract["values"]
  def badge_sizes, do: @size_contract["values"]

  attr(:style, :string,
    values: @appearance_contract["values"],
    default: @appearance_contract["default"],
    doc: @appearance_contract["description"]
  )

  attr(:label, :string, required: true, doc: @label_contract["description"])

  attr(:color, :string,
    values: @color_contract["values"],
    default: @color_contract["default"],
    doc: @color_contract["description"]
  )

  attr(:size, :string,
    values: @size_contract["values"],
    default: @size_contract["default"],
    doc: @size_contract["description"]
  )

  attr(:disabled, :boolean,
    default: @disabled_contract["default"],
    doc: @disabled_contract["description"]
  )

  attr(:dot, :boolean, default: @dot_contract["default"], doc: @dot_contract["description"])

  attr(:icon_only, :boolean,
    default: @icon_only_contract["default"],
    doc: @icon_only_contract["description"]
  )

  slot(:icon, doc: "The icon to render next to the label. Overrides the `dot` attribute.")

  attr(:rest, :global)

  def badge(assigns) do
    ~H"""
    <span
      class={badge_class()}
      data-style={@style}
      data-color={@color}
      data-size={@size}
      data-disabled={@disabled}
      data-dot={@dot}
      data-icon={has_slot_content?(@icon, assigns)}
      data-icon-only={@icon_only}
      {@rest}
    >
      <%= if @dot || has_slot_content?(@icon, assigns) do %>
        <div data-part="icon">
          <%= if has_slot_content?(@icon, assigns) do %>
            {render_slot(@icon)}
          <% else %>
            <.small_dot :if={@size == "small"} />
            <.large_dot :if={@size == "large"} />
          <% end %>
        </div>
      <% end %>
      <span :if={!@icon_only}>{@label}</span>
    </span>
    """
  end

  attr(:type, :string,
    values: ~w(icon dot),
    default: "icon",
    doc: "Whether to render the prefix as a dot, or a status-specific icon"
  )

  attr(:status, :string,
    values: ~w(success error warning attention disabled in_progress),
    required: true,
    doc: "The status of the badge"
  )

  attr(:label, :string, required: true, doc: "The label of the badge")
  attr(:rest, :global)

  def status_badge(assigns) do
    ~H"""
    <span class="noora-status-badge" data-status={@status} {@rest}>
      <span data-part="icon">
        <.status_icon :if={@type == "icon"} status={@status} />
        <.large_dot :if={@type == "dot"} />
      </span>
      <span data-part="label">{@label}</span>
    </span>
    """
  end

  def status_icon(%{status: "success"} = assigns) do
    ~H"""
    <.circle_check />
    """
  end

  def status_icon(%{status: "error"} = assigns) do
    ~H"""
    <.alert_circle />
    """
  end

  def status_icon(%{status: "warning"} = assigns) do
    ~H"""
    <.alert_hexagon />
    """
  end

  def status_icon(%{status: "attention"} = assigns) do
    ~H"""
    <.alert_triangle />
    """
  end

  def status_icon(%{status: "disabled"} = assigns) do
    ~H"""
    <.cancel />
    """
  end

  def status_icon(%{status: "in_progress"} = assigns) do
    ~H"""
    <.circle_dashed />
    """
  end

  defp small_dot(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 12 12" fill="none">
      <rect x="4" y="4" width="4" height="4" rx="1" fill="#FDFDFD" />
    </svg>
    """
  end

  defp large_dot(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16" fill="none">
      <rect x="5" y="5" width="6" height="6" rx="1.33333" fill="currentColor" />
    </svg>
    """
  end

  defp badge_class, do: @badge_class
end
