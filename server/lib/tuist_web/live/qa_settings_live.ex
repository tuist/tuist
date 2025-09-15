defmodule TuistWeb.QASettingsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Authorization
  alias Tuist.QA
  alias Tuist.QA.LaunchArgumentGroup
  alias Tuist.Repo

  @impl true
  def mount(_params, _uri, %{assigns: %{selected_project: selected_project, current_user: current_user}} = socket) do
    if Authorization.authorize(:project_update, current_user, selected_project) != :ok do
      raise TuistWeb.Errors.UnauthorizedError,
            gettext("You are not authorized to perform this action.")
    end

    selected_project = Repo.preload(selected_project, :qa_launch_argument_groups)

    add_launch_argument_form =
      %LaunchArgumentGroup{}
      |> LaunchArgumentGroup.create_changeset(%{})
      |> to_form(as: :launch_argument_group)

    edit_launch_argument_form =
      %LaunchArgumentGroup{}
      |> LaunchArgumentGroup.create_changeset(%{})
      |> to_form(as: :launch_argument_group)

    edit_launch_argument_forms =
      Map.new(selected_project.qa_launch_argument_groups, fn group ->
        form =
          group
          |> LaunchArgumentGroup.update_changeset(%{})
          |> to_form(as: :launch_argument_group)

        {group.id, form}
      end)

    socket =
      socket
      |> assign(:selected_project, selected_project)
      |> assign(:add_launch_argument_form, add_launch_argument_form)
      |> assign(:edit_launch_argument_form, edit_launch_argument_form)
      |> assign(:edit_launch_argument_forms, edit_launch_argument_forms)
      |> assign(:head_title, "#{gettext("QA Settings")} · #{selected_project.name} · Tuist")

    {:ok, socket}
  end

  @impl true
  def handle_event("create_launch_argument_group", %{"launch_argument_group" => params}, socket) do
    params = Map.put(params, "project_id", socket.assigns.selected_project.id)

    case QA.create_launch_argument_group(params) do
      {:ok, _launch_argument_group} ->
        selected_project =
          Repo.preload(socket.assigns.selected_project, :qa_launch_argument_groups, force: true)

        add_launch_argument_form =
          %LaunchArgumentGroup{name: "", description: "", value: ""}
          |> LaunchArgumentGroup.create_changeset(%{})
          |> to_form(as: :launch_argument_group)

        edit_launch_argument_forms =
          Map.new(selected_project.qa_launch_argument_groups, fn group ->
            form =
              group
              |> LaunchArgumentGroup.update_changeset(%{})
              |> to_form(as: :launch_argument_group)

            {group.id, form}
          end)

        socket =
          socket
          |> assign(:selected_project, selected_project)
          |> assign(:add_launch_argument_form, add_launch_argument_form)
          |> assign(:edit_launch_argument_forms, edit_launch_argument_forms)
          |> push_event("close-modal", %{id: "add-launch-argument-modal"})

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, add_launch_argument_form: to_form(changeset))}
    end
  end

  @impl true
  def handle_event("close_add_launch_argument_modal", _params, socket) do
    socket = push_event(socket, "close-modal", %{id: "add-launch-argument-modal"})

    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "delete_launch_argument_group",
        %{"id" => id} = _params,
        %{assigns: %{selected_project: selected_project}} = socket
      ) do
    {:ok, _} =
      selected_project.qa_launch_argument_groups
      |> Enum.find(&(&1.id == id))
      |> QA.delete_launch_argument_group()

    selected_project =
      Repo.preload(socket.assigns.selected_project, :qa_launch_argument_groups, force: true)

    edit_launch_argument_forms =
      Map.new(selected_project.qa_launch_argument_groups, fn group ->
        form =
          group
          |> LaunchArgumentGroup.update_changeset(%{})
          |> to_form(as: :launch_argument_group)

        {group.id, form}
      end)

    socket =
      socket
      |> assign(:selected_project, selected_project)
      |> assign(:edit_launch_argument_forms, edit_launch_argument_forms)

    {:noreply, socket}
  end

  @impl true
  def handle_event("update_launch_argument_group", %{"id" => id, "launch_argument_group" => params}, socket) do
    launch_argument_group =
      Enum.find(socket.assigns.selected_project.qa_launch_argument_groups, &(&1.id == id))

    case QA.update_launch_argument_group(launch_argument_group, params) do
      {:ok, _launch_argument_group} ->
        selected_project =
          Repo.preload(socket.assigns.selected_project, :qa_launch_argument_groups, force: true)

        edit_launch_argument_forms =
          Map.new(selected_project.qa_launch_argument_groups, fn group ->
            form =
              group
              |> LaunchArgumentGroup.update_changeset(%{})
              |> to_form(as: :launch_argument_group)

            {group.id, form}
          end)

        socket =
          socket
          |> assign(:selected_project, selected_project)
          |> assign(:edit_launch_argument_forms, edit_launch_argument_forms)
          |> push_event("close-modal", %{id: "edit-launch-argument-modal-#{id}"})

        {:noreply, socket}

      {:error, changeset} ->
        updated_forms = Map.put(socket.assigns.edit_launch_argument_forms, id, to_form(changeset))
        {:noreply, assign(socket, edit_launch_argument_forms: updated_forms)}
    end
  end

  @impl true
  def handle_event("close_edit_launch_argument_modal", %{"id" => id} = _params, socket) do
    socket = push_event(socket, "close-modal", %{id: "edit-launch-argument-modal-#{id}"})
    {:noreply, socket}
  end
end
