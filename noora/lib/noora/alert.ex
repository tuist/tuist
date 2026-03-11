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
    values: ~w(information warning error success),
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

  attr(:title, :string, required: true, doc: "The title of the alert.")

  attr(:description, :string,
    default: nil,
    doc: "The description of the alert. Only shown if `size` is large."
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
        <.icon status={@status} />
        <span data-part="title">{@title}</span>
        <div :if={@action != []} data-part="actions">
          <%= for action <- @action do %>
            {render_slot(action)}
          <% end %>
        </div>
        <.dismiss_icon
          :if={@dismissible}
          size={if @size == "small", do: "small", else: "large"}
          data-part="dismiss-icon"
          phx-click={JS.hide(to: "##{@id}")}
        />
      <% end %>
      <%= if @size == "large" do %>
        <.icon status={@status} />
        <div data-part="column">
          <span data-part="title">{@title}</span>
          <span data-part="description">{@description}</span>
          <div :if={@action != []} data-part="actions">
            <div :for={action <- @action}>
              {render_slot(action)}
            </div>
          </div>
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
