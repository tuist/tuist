defmodule TuistWeb.ProjectsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Previews.PlatformIcon

  alias Tuist.AppBuilds
  alias Tuist.Authorization
  alias Tuist.Projects
  alias Tuist.Projects.Project
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Utilities.Query

  @pagination_threshold 6

  @impl true
  def mount(_params, _uri, socket) do
    selected_account = socket.assigns[:selected_account]
    current_user = socket.assigns[:current_user]

    if Authorization.authorize(:projects_read, current_user, selected_account) != :ok do
      raise TuistWeb.Errors.NotFoundError,
            dgettext("dashboard_projects", "The page you are looking for doesn't exist or has been moved.")
    end

    form = to_form(Project.create_changeset(%{}))

    {:ok,
     socket
     |> assign(:form, form)
     |> assign(:selected_tab, "projects")
     |> assign(:head_title, "#{dgettext("dashboard_projects", "Projects")} · #{selected_account.name} · Tuist")
     |> assign(:pagination_threshold, @pagination_threshold)}
  end

  @impl true
  def handle_params(params, uri, socket) do
    selected_account = socket.assigns[:selected_account]
    total_project_count = Projects.get_project_count_for_account(selected_account)

    {:noreply,
     socket
     |> assign(:total_project_count, total_project_count)
     |> assign_projects(params, total_project_count)
     |> assign(:search_term, Map.get(params, "search", ""))
     |> assign(:uri, URI.parse(uri))}
  end

  defp assign_projects(socket, _params, total_project_count) when total_project_count <= @pagination_threshold do
    selected_account = socket.assigns[:selected_account]
    all_project_accounts = Projects.get_all_project_accounts(selected_account)

    all_projects_with_interaction =
      all_project_accounts
      |> Enum.map(&Map.get(&1, :project))
      |> Projects.list_sorted_with_interaction_data(preload: [:previews])

    socket
    |> assign(:all_projects, all_projects_with_interaction)
    |> assign(:recent_projects, [])
    |> assign(:projects_meta, %{has_previous_page?: false, has_next_page?: false})
  end

  defp assign_projects(socket, params, _total_project_count) do
    selected_account = socket.assigns[:selected_account]
    recent_projects = Projects.get_recent_projects_for_account(selected_account)

    # Build Flop options for pagination and search
    flop_filters = [
      %{field: :account_id, op: :==, value: selected_account.id}
    ]

    # Add search filter if present
    flop_filters =
      case Map.get(params, "search") do
        nil ->
          flop_filters

        "" ->
          flop_filters

        search_term ->
          [%{field: :name, op: :=~, value: search_term} | flop_filters]
      end

    flop_options = %{
      filters: flop_filters,
      order_by: [:name],
      order_directions: [:asc]
    }

    # Apply pagination
    flop_options =
      cond do
        not is_nil(Map.get(params, "before")) ->
          flop_options
          |> Map.put(:last, @pagination_threshold)
          |> Map.put(:before, Map.get(params, "before"))

        not is_nil(Map.get(params, "after")) ->
          flop_options
          |> Map.put(:first, @pagination_threshold)
          |> Map.put(:after, Map.get(params, "after"))

        true ->
          Map.put(flop_options, :first, @pagination_threshold)
      end

    {all_projects, projects_meta} =
      Projects.list_projects(flop_options, preload: [:previews], include_interaction_data: true)

    socket
    |> assign(:recent_projects, recent_projects)
    |> assign(:all_projects, all_projects)
    |> assign(:projects_meta, projects_meta)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="projects">
      <div data-part="row">
        <h2 data-part="title">{dgettext("dashboard_projects", "Projects")}</h2>
        <.create_project_form id="create-project-form" form={@form} source="header" />
      </div>

      <%= if @total_project_count <= @pagination_threshold do %>
        <!-- Simple layout for <%= @pagination_threshold %> or fewer projects -->
        <div data-part="grid">
          <div :if={Enum.empty?(@all_projects)} data-part="empty-state">
            <.create_project_form
              id="create-project-form-empty-state"
              form={@form}
              source="empty-state"
            />
            <.project_background />
          </div>
          <div
            :for={project <- @all_projects}
            data-part="project"
            phx-click="navigate"
            phx-value-project={project.name}
          >
            <.project_background />
            <div data-part="title">
              {project.name}
            </div>
            <div
              :if={Enum.any?(Projects.platforms(project, device_platforms_only?: true))}
              data-part="platforms"
            >
              <h3>Supported platforms</h3>
              <div data-part="tags">
                <.tag
                  :for={
                    platform <- Enum.sort(Projects.platforms(project, device_platforms_only?: true))
                  }
                  label={AppBuilds.platform_string(platform)}
                  icon={platform_icon_name(platform)}
                />
              </div>
            </div>
            <span :if={project.last_interacted_at} data-part="time">
              {dgettext("dashboard_projects", "Last interacted with %{time}", %{
                time: DateFormatter.from_now(project.last_interacted_at)
              })}
            </span>
            <span :if={!project.last_interacted_at} data-part="time">
              {dgettext("dashboard_projects", "Created %{time}", %{
                time: DateFormatter.from_now(project.created_at)
              })}
            </span>
          </div>
        </div>
      <% else %>
        <!-- Complex layout for 7+ projects -->
        <!-- Recent projects section -->
        <div :if={Enum.any?(@recent_projects)} data-part="recent-section">
          <h3 data-part="section-title">{dgettext("dashboard_projects", "Recent projects")}</h3>
          <div data-part="grid">
            <div
              :for={project <- @recent_projects}
              data-part="project"
              phx-click="navigate"
              phx-value-project={project.name}
            >
              <.project_background />
              <div data-part="title">
                {project.name}
              </div>
              <div
                :if={Enum.any?(Projects.platforms(project, device_platforms_only?: true))}
                data-part="platforms"
              >
                <h3>{dgettext("dashboard_projects", "Supported platforms")}</h3>
                <div data-part="tags">
                  <.tag
                    :for={
                      platform <- Enum.sort(Projects.platforms(project, device_platforms_only?: true))
                    }
                    label={AppBuilds.platform_string(platform)}
                    icon={platform_icon_name(platform)}
                  />
                </div>
              </div>
              <span :if={project.last_interacted_at} data-part="time">
                {dgettext("dashboard_projects", "Last interacted with %{time}", %{
                  time: DateFormatter.from_now(project.last_interacted_at)
                })}
              </span>
              <span :if={!project.last_interacted_at} data-part="time">
                {dgettext("dashboard_projects", "Created %{time}", %{
                  time: DateFormatter.from_now(project.created_at)
                })}
              </span>
            </div>
          </div>
        </div>
        
    <!-- All projects section -->
        <div data-part="all-section">
          <h3 data-part="section-title">{dgettext("dashboard_projects", "All projects")}</h3>
          <.form
            for={%{}}
            phx-change="search"
            phx-submit="search"
            data-part="search-form"
            id="projects-search-form"
          >
            <.text_input
              id="projects-search-input"
              name="search"
              value={@search_term}
              placeholder={dgettext("dashboard_projects", "Search projects...")}
              phx-debounce="100"
            />
          </.form>

          <div data-part="grid">
            <div :if={Enum.empty?(@all_projects)} data-part="empty-state">
              <.create_project_form
                id="create-project-form-empty-state"
                form={@form}
                source="empty-state"
              />
              <.project_background />
            </div>
            <div
              :for={project <- @all_projects}
              data-part="project"
              phx-click="navigate"
              phx-value-project={project.name}
            >
              <.project_background />
              <div data-part="title">
                {project.name}
              </div>
              <div
                :if={Enum.any?(Projects.platforms(project, device_platforms_only?: true))}
                data-part="platforms"
              >
                <h3>Supported platforms</h3>
                <div data-part="tags">
                  <.tag
                    :for={
                      platform <- Enum.sort(Projects.platforms(project, device_platforms_only?: true))
                    }
                    label={AppBuilds.platform_string(platform)}
                    icon={platform_icon_name(platform)}
                  />
                </div>
              </div>
              <span :if={project.last_interacted_at} data-part="time">
                {dgettext("dashboard_projects", "Last interacted with %{time}", %{
                  time: DateFormatter.from_now(project.last_interacted_at)
                })}
              </span>
              <span :if={!project.last_interacted_at} data-part="time">
                {dgettext("dashboard_projects", "Created %{time}", %{
                  time: DateFormatter.from_now(project.created_at)
                })}
              </span>
            </div>
          </div>

          <.pagination
            :if={@projects_meta.has_previous_page? or @projects_meta.has_next_page?}
            uri={@uri}
            has_previous_page={@projects_meta.has_previous_page?}
            has_next_page={@projects_meta.has_next_page?}
            start_cursor={@projects_meta.start_cursor}
            end_cursor={@projects_meta.end_cursor}
          />
        </div>
      <% end %>
    </div>
    """
  end

  defp create_project_form(assigns) do
    ~H"""
    <.form id={@id} for={@form} phx-submit="create-project">
      <.modal
        id={"#{@id}-modal"}
        title={dgettext("dashboard_projects", "Create project")}
        on_dismiss="close-create-project"
      >
        <:trigger :let={attrs}>
          <.button
            :if={@source == "header"}
            variant="primary"
            label={dgettext("dashboard_projects", "New project")}
            {attrs}
          />
          <.button
            :if={@source == "empty-state"}
            variant="secondary"
            size="medium"
            label={dgettext("dashboard_projects", "Create a new project")}
            {attrs}
          />
        </:trigger>
        <.line_divider />
        <.text_input
          id={"#{@id}-input"}
          field={@form[:name]}
          label={dgettext("dashboard_projects", "Name")}
        />
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

  def handle_event("search", %{"search" => search_term}, socket) do
    query_string =
      socket.assigns.uri.query
      |> Query.put("search", search_term)
      |> Query.drop("after")
      |> Query.drop("before")

    path =
      "/#{socket.assigns.selected_account.name}/projects" <>
        if query_string == "", do: "", else: "?#{query_string}"

    {:noreply, push_patch(socket, to: path)}
  end

  def handle_event("create-project", %{"project" => %{"name" => name}}, socket) do
    account = socket.assigns.selected_account

    with :ok <- Authorization.authorize(:project_create, socket.assigns.current_user, account),
         {:ok, _project} <- Projects.create_project(%{name: name, account: account}) do
      socket =
        socket
        |> push_event("close-modal", %{id: "create-project-form-modal"})
        |> push_event("close-modal", %{id: "create-project-form-empty-state-modal"})
        |> push_patch(to: ~p"/#{account.name}/projects")

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
