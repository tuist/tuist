defmodule Noora.Alert do
  @moduledoc """
  An alert component.

  ## Example

  ```elixir
  <.alert status="success" title="Operation completed successfully" />
  ```
  """

  use Phoenix.Component

  import Noora.DismissIcon

  alias Noora.Icon
  alias Phoenix.LiveView.JS

  attr(:id, :string, default: nil)

  attr(:type, :string,
    values: ~w(primary secondary),
    default: "primary",
    doc: "The type of alert."
  )

  attr(:status, :string,
    values: ~w(default information warning error success),
    required: true,
    doc: "The status of the alert."
  )

  attr(:size, :string,
    values: ~w(small medium large),
    default: "medium",
    doc: "The size of the alert."
  )

  attr(:dismissible, :boolean,
    default: false,
    doc: "Whether the alert can be dismissed."
  )

  attr(:show_icon, :boolean, default: true, doc: "Whether to show the status icon.")

  attr(:title, :string, required: true, doc: "The title of the alert.")

  attr(:description, :string,
    default: nil,
    doc: "The description of the alert. Only shown if `size` is large."
  )

  slot(:inner_block,
    required: false,
    doc: "Rich HTML description. Takes precedence over the `description` attribute when provided."
  )

  slot(:action, required: false)

  attr(:rest, :global)

  def alert(assigns) do
    ~H"""
    <div
      id={@id}
      class="noora-alert"
      data-type={@type}
      data-status={@status}
      data-size={@size}
      {@rest}
    >
      <%= if @size in ["small", "medium"] do %>
        <.icon :if={@show_icon} status={@status} />
        <span data-part="title">{@title}</span>
        <.actions actions={@action} />
        <.dismiss_icon
          :if={@dismissible}
          size={if @size == "small", do: "small", else: "large"}
          data-part="dismiss-icon"
          phx-click={JS.hide(to: "##{@id}")}
        />
      <% end %>
      <%= if @size == "large" do %>
        <.icon :if={@show_icon} status={@status} />
        <div data-part="column">
          <span data-part="title">{@title}</span>
          <div :if={@inner_block != []} data-part="description">
            <span :if={@description}>{@description}</span>
            {render_slot(@inner_block)}
          </div>
          <span :if={@inner_block == [] and @description} data-part="description">
            {@description}
          </span>
          <.actions actions={@action} />
        </div>
        <.dismiss_icon
          :if={@dismissible}
          size="large"
          data-part="dismiss-icon"
          phx-click={JS.hide(to: "##{@id}")}
        />
      <% end %>
    </div>
    """
  end

  defp actions(assigns) do
    ~H"""
    <div :if={@actions != []} data-part="actions">
      <%= for {action, index} <- Enum.with_index(@actions) do %>
        <span :if={index > 0} data-part="action-separator" aria-hidden="true"></span>
        <div data-part="action">{render_slot(action)}</div>
      <% end %>
    </div>
    """
  end

  defp icon(%{status: "default"} = assigns) do
    ~H"""
    <div data-part="icon">
      <Icon.apps />
    </div>
    """
  end

  defp icon(%{status: status} = assigns) when status in ["error", "information"] do
    ~H"""
    <div data-part="icon">
      <Icon.alert_circle />
    </div>
    """
  end

  defp icon(%{status: "success"} = assigns) do
    ~H"""
    <div data-part="icon">
      <Icon.circle_check />
    </div>
    """
  end

  defp icon(%{status: "warning"} = assigns) do
    ~H"""
    <div data-part="icon">
      <Icon.alert_triangle />
    </div>
    """
  end
end
