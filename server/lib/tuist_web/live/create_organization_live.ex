defmodule TuistWeb.CreateOrganizationLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Accounts
  alias Tuist.Accounts.Organization

  @impl true
  def mount(_params, _session, socket) do
    form = to_form(Organization.create_changeset())
    socket = assign(socket, form: form)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="create-organization">
      <div data-part="wrapper">
        <div data-part="frame">
          <div data-part="content">
            <img src="/images/tuist_logo_32x32@2x.png" alt={gettext("Tuist Logo")} data-part="logo" />
            <div data-part="dots">
              <.dots_light />
              <.dots_dark />
            </div>
            <div data-part="header">
              <span data-part="subtitle">
                {gettext("Create an organization account to continue")}
              </span>
              <h1 data-part="title">{gettext("Create a new organization")}</h1>
            </div>
            <.form
              data-part="form"
              for={@form}
              id="create-project-form"
              phx-submit="create_organization"
            >
              <.text_input
                id="organization-name"
                field={@form[:name]}
                type="basic"
                label={gettext("Name")}
                show_required
                required
              />
              <div data-part="actions">
                <.button type="submit" variant="primary" label={gettext("Create organization")} />
                <.button navigate={~p"/projects/new"} variant="secondary" label={gettext("Cancel")} />
              </div>
            </.form>
          </div>
        </div>
      </div>
      <div data-part="background">
        <div data-part="top-right-gradient"></div>
        <div data-part="bottom-left-gradient"></div>
        <div data-part="shell"><.shell /></div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("select_account", %{"value" => [value]}, socket) do
    socket = assign(socket, selected_account: String.to_integer(value))

    {:noreply, socket}
  end

  @impl true
  def handle_event("create_organization", %{"organization" => %{"name" => name}}, socket) do
    case Accounts.create_organization(%{name: name, creator: socket.assigns.current_user}) do
      {:ok, organization} ->
        socket =
          socket
          |> put_flash(:organization_id, organization.id)
          |> push_navigate(to: ~p"/projects/new")

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}

      _error ->
        {:noreply, socket}
    end
  end
end
