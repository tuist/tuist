defmodule TuistWeb.ProjectsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Previews.PlatformIcon

  alias Tuist.Authorization
  alias Tuist.Previews
  alias Tuist.Projects
  alias Tuist.Projects.Project

  @impl true
  def mount(_params, _uri, socket) do
    selected_account = socket.assigns[:selected_account]
    current_user = socket.assigns[:current_user]

    if not Tuist.Authorization.can(current_user, :read, selected_account, :projects) do
      raise TuistWeb.Errors.NotFoundError,
            gettext("The page you are looking for doesn't exist or has been moved.")
    end

    projects =
      selected_account
      |> Projects.get_all_project_accounts()
      |> Enum.map(&Map.get(&1, :project))
      |> Tuist.Repo.preload(:previews)
      |> Enum.sort_by(&(Projects.get_last_command_event_date(&1) || &1.created_at), :desc)

    form = to_form(Project.create_changeset(%{}))

    {:ok,
     socket
     |> assign(:projects, projects)
     |> assign(:form, form)
     |> assign(:selected_tab, "projects")
     |> assign(:head_title, "#{gettext("Projects")} · #{selected_account.name} · Tuist")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="projects">
      <div data-part="row">
        <h2 data-part="title">{gettext("Projects")}</h2>
        <.create_project_form id="create-project-form" form={@form} source="header" />
      </div>
      <div data-part="grid">
        <div :if={Enum.empty?(@projects)} data-part="empty-state">
          <.create_project_form
            id="create-project-form-empty-state"
            form={@form}
            source="empty-state"
          />
          <.project_background />
        </div>
        <div
          :for={project <- @projects}
          data-part="project"
          phx-click="navigate"
          phx-value-project={project.name}
        >
          <.project_background />
          <div data-part="title">
            {project.name}
          </div>
          <div :if={Enum.any?(Projects.platforms(project))} data-part="platforms">
            <h3>Supported platforms</h3>
            <div data-part="tags">
              <.tag
                :for={platform <- Projects.platforms(project)}
                label={Previews.platform_string(platform)}
                icon={platform_icon_name(platform)}
              />
            </div>
          </div>
          <span :if={Projects.get_last_command_event_date(project)} data-part="time">
            {gettext("Last interacted with %{time}", %{
              time: Timex.from_now(Projects.get_last_command_event_date(project))
            })}
          </span>
          <span :if={!Projects.get_last_command_event_date(project)} data-part="time">
            {gettext("Created %{time}", %{time: Timex.from_now(project.created_at)})}
          </span>
        </div>
      </div>
    </div>
    """
  end

  defp create_project_form(assigns) do
    ~H"""
    <.form id={@id} for={@form} phx-submit="create-project">
      <.modal id={"#{@id}-modal"} title={gettext("Create project")} on_dismiss="close-create-project">
        <:trigger :let={attrs}>
          <.button :if={@source == "header"} variant="primary" label={gettext("New project")} {attrs} />
          <.button
            :if={@source == "empty-state"}
            variant="secondary"
            size="medium"
            label={gettext("Create a new project")}
            {attrs}
          />
        </:trigger>
        <.line_divider />
        <.text_input id={"#{@id}-input"} field={@form[:name]} label={gettext("Name")} />
        <.line_divider />
        <:footer>
          <.modal_footer>
            <:action>
              <.button
                label="Cancel"
                variant="secondary"
                type="button"
                phx-click="close-create-project"
              />
            </:action>
            <:action>
              <.button label="Save" type="submit" />
            </:action>
          </.modal_footer>
        </:footer>
      </.modal>
    </.form>
    """
  end

  @impl true
  def handle_event("navigate", %{"project" => project}, socket) do
    socket =
      push_navigate(socket, to: ~p"/#{socket.assigns.selected_account.name}/#{project}")

    {:noreply, socket}
  end

  def handle_event("create-project", %{"project" => %{"name" => name}}, socket) do
    account = socket.assigns.selected_account

    with true <- Authorization.can(socket.assigns.current_user, :create, account, :project),
         {:ok, project} <- Projects.create_project(%{name: name, account: account}) do
      socket =
        socket
        |> assign(projects: [project | socket.assigns.projects])
        |> push_event("close-modal", %{id: "create-project-form-modal"})
        |> push_event("close-modal", %{id: "create-project-form-empty-state-modal"})

      {:noreply, socket}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("close-create-project", _, socket) do
    socket =
      socket
      |> push_event("close-modal", %{id: "create-project-form-modal"})
      |> push_event("close-modal", %{id: "create-project-form-empty-state-modal"})

    {:noreply, socket}
  end

  defp project_background(assigns) do
    ~H"""
    <svg viewBox="0 0 292 196" fill="none" xmlns="http://www.w3.org/2000/svg" data-part="background">
      <mask
        id="mask0_1989_22018"
        style="mask-type:alpha"
        maskUnits="userSpaceOnUse"
        x="0"
        y="-1"
        width="292"
        height="198"
      >
        <rect
          x="0.5"
          y="-0.5"
          width="291"
          height="197"
          fill="url(#paint0_radial_1989_22018)"
          fill-opacity="0.2"
        />
      </mask>
      <g mask="url(#mask0_1989_22018)">
        <path d="M11 149.75H281" />
        <path d="M11 98H281" />
        <path d="M11 46.25H281" />
        <path d="M197.751 233V-37" />
        <path d="M146 233V-37" />
        <path d="M94.2501 233V-37" />
        <path d="M281 233L11 -37" />
        <path d="M11 233L281 -37" />
        <rect x="29" y="-19" width="234" height="234" />
        <circle cx="146" cy="98" r="51.75" />
        <circle cx="146" cy="98" r="74.25" />
        <circle cx="146" cy="98" r="117" />
      </g>
      <defs>
        <radialGradient
          id="paint0_radial_1989_22018"
          cx="0"
          cy="0"
          r="1"
          gradientUnits="userSpaceOnUse"
          gradientTransform="translate(146 98) rotate(90) scale(99 146)"
        >
          <stop stop-color="white" />
          <stop offset="1" stop-color="white" stop-opacity="0" />
        </radialGradient>
      </defs>
    </svg>
    """
  end
end
