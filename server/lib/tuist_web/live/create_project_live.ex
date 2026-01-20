defmodule TuistWeb.CreateProjectLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Phoenix.Flash
  alias Tuist.Accounts
  alias Tuist.Authorization
  alias Tuist.Projects
  alias Tuist.Projects.Project

  @impl true
  def mount(_params, _session, socket) do
    form = to_form(Project.create_changeset(%{}))

    current_user = socket.assigns.current_user

    organization_accounts =
      current_user |> Accounts.get_user_organization_accounts() |> Enum.map(& &1.account)

    selected_account =
      if Flash.get(socket.assigns.flash, :organization_id) do
        organization_accounts
        |> Enum.find(&(&1.organization_id == Flash.get(socket.assigns.flash, :organization_id)))
        |> Map.get(:id)
      else
        current_user.account.id
      end

    socket =
      assign(socket,
        form: form,
        selected_account: selected_account,
        accounts: [current_user.account | organization_accounts]
      )

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="create-project">
      <div data-part="wrapper">
        <div data-part="frame">
          <div data-part="content">
            <img
              src="/images/tuist_logo_32x32@2x.png"
              alt={dgettext("dashboard_projects", "Tuist Logo")}
              data-part="logo"
            />
            <div data-part="dots">
              <.dots_light />
              <.dots_dark />
            </div>
            <div data-part="header">
              <h1 data-part="title">{dgettext("dashboard_projects", "Create a project")}</h1>
              <span data-part="subtitle">
                {dgettext("dashboard_projects", "Create a Tuist project to continue")}
              </span>
            </div>
            <.form data-part="form" for={@form} id="create-project-form" phx-submit="create_project">
              <.text_input
                field={@form[:name]}
                type="basic"
                label={dgettext("dashboard_projects", "Name")}
                show_required={false}
                required
              />
              <div data-part="dropdown">
                <.label label={dgettext("dashboard_projects", "Select account")} />
                <.select
                  id="account-selection"
                  name="account_id"
                  label={dgettext("dashboard_projects", "Account")}
                  hint={
                    dgettext(
                      "dashboard_projects",
                      "Choose an account to create your project or set up a new organization."
                    )
                  }
                  value={@selected_account}
                  on_value_change="select_account"
                >
                  <:item
                    :for={account <- @accounts}
                    value={account.id}
                    label={account.name}
                    icon={if is_nil(account.organization_id), do: "user", else: "building"}
                  />
                </.select>
              </div>

              <.button
                variant="primary"
                label={dgettext("dashboard_projects", "Continue")}
                type="submit"
              />
              <.line_divider text={dgettext("dashboard_projects", "Or set up a new organization")} />
              <.button
                label={dgettext("dashboard_projects", "Create organization")}
                variant="secondary"
                navigate={~p"/organizations/new"}
              />
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
  def handle_event("create_project", %{"project" => params}, socket) do
    with {:ok, account} <- Accounts.get_account_by_id(socket.assigns.selected_account),
         :ok <- Authorization.authorize(:project_create, socket.assigns.current_user, account),
         {:ok, project} <- Projects.create_project(%{name: params["name"], account: account}) do
      {:noreply,
       push_navigate(socket,
         to: ~p"/#{account.name}/#{project.name}/connect"
       )}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}

      _error ->
        # TODO: Error handling
        {:noreply, socket}
    end
  end
end
