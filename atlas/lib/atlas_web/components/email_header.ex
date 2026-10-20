defmodule AtlasWeb.EmailHeader do
  @moduledoc """
  Title and section tabs shared by the email pages.
  """
  use Phoenix.Component
  use Noora
  use Gettext, backend: AtlasWeb.Gettext
  use AtlasWeb, :verified_routes

  alias Atlas.Mailbox

  attr :selected, :atom, required: true, values: [:audiences, :inbox, :outbox]

  def email_header(assigns) do
    assigns = assign(assigns, :address, Mailbox.address())

    ~H"""
    <div data-part="header">
      <div data-part="text">
        <h1 data-part="title">{gettext("Email")}</h1>
        <p data-part="description">
          {gettext("Subscribers, audiences, and every email received at or sent from %{address}.",
            address: @address
          )}
        </p>
      </div>
    </div>

    <.tab_menu_horizontal
      id="email-tabs"
      data-part="email-tabs"
      aria-label={gettext("Email sections")}
    >
      <.tab_menu_horizontal_item
        id="email-audiences-tab"
        navigate={~p"/outbound/email"}
        label={gettext("Audiences")}
        selected={@selected == :audiences}
      />
      <.tab_menu_horizontal_item
        id="email-inbox-tab"
        navigate={~p"/outbound/email/inbox"}
        label={gettext("Inbox")}
        selected={@selected == :inbox}
      />
      <.tab_menu_horizontal_item
        id="email-outbox-tab"
        navigate={~p"/outbound/email/outbox"}
        label={gettext("Outbox")}
        selected={@selected == :outbox}
      />
    </.tab_menu_horizontal>
    """
  end
end
