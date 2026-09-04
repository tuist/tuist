defmodule TuistWeb.ProjectSettingsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Authorization
  alias Tuist.Projects
  alias Tuist.Projects.Project
  alias TuistWeb.Helpers.OpenGraph

  @logo_max_size 2 * 1024 * 1024

  @impl true
  def mount(_params, _uri, %{assigns: %{selected_project: selected_project, current_user: current_user}} = socket) do
    if Authorization.authorize(:project_update, current_user, selected_project) != :ok do
      raise TuistWeb.Errors.UnauthorizedError,
            dgettext("dashboard_projects", "You are not authorized to perform this action.")
    end

    rename_project_form = to_form(Project.update_changeset(selected_project, %{}))
    default_branch_form = to_form(Project.update_changeset(selected_project, %{}))
    delete_project_form = to_form(%{"name" => ""})

    socket =
      socket
      |> assign(rename_project_form: rename_project_form)
      |> assign(default_branch_form: default_branch_form)
      |> assign(delete_project_form: delete_project_form)
      |> assign(:head_title, "#{dgettext("dashboard_projects", "Settings")} · #{selected_project.name} · Tuist")
      |> assign(OpenGraph.og_image_assigns("settings"))
      |> allow_upload(:logo,
        accept: ~w(.png .jpg .jpeg .webp),
        max_entries: 1,
        max_file_size: @logo_max_size
      )

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "rename_project",
        %{"project" => %{"name" => name}} = _params,
        %{assigns: %{selected_project: selected_project, selected_account: selected_account}} = socket
      ) do
    case Projects.update_project(selected_project, %{name: name}) do
      {:ok, project} ->
        socket =
          socket
          |> push_event("close-modal", %{id: "rename-project-modal"})
          |> push_navigate(to: ~p"/#{selected_account.name}/#{project.name}/settings")

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, rename_project_form: to_form(changeset))}
    end
  end

  def handle_event("close_rename_project_modal", _params, socket) do
    socket =
      socket
      |> push_event("close-modal", %{id: "rename-project-modal"})
      |> assign(rename_project_form: to_form(Project.update_changeset(socket.assigns.selected_project, %{})))

    {:noreply, socket}
  end

  def handle_event(
        "delete_project",
        %{"name" => name} = _params,
        %{assigns: %{selected_project: project, selected_account: account}} = socket
      ) do
    socket =
      if name == project.name do
        Projects.delete_project(project)

        socket
        |> push_event("close-modal", %{id: "delete-project-modal"})
        |> push_navigate(to: ~p"/#{account.name}")
      else
        assign(socket, delete_project_form: to_form(%{"name" => ""}))
      end

    {:noreply, socket}
  end

  def handle_event("close_delete_project_modal", _params, socket) do
    socket =
      socket
      |> push_event("close-modal", %{id: "delete-project-modal"})
      |> assign(delete_project_form: to_form(%{"name" => ""}))

    {:noreply, socket}
  end

  def handle_event(
        "update_default_branch",
        %{"project" => %{"default_branch" => default_branch}},
        %{assigns: %{selected_project: selected_project}} = socket
      ) do
    # `Ecto.Changeset.cast` substitutes the schema default ("main") for an
    # empty string, so a blank submission would silently reset the branch
    # instead of being rejected. Guard against it here before casting.
    case String.trim(default_branch) do
      "" ->
        changeset =
          selected_project
          |> Project.update_changeset(%{})
          |> Ecto.Changeset.add_error(:default_branch, dgettext("dashboard_projects", "can't be blank"))
          |> Map.put(:action, :update)

        {:noreply, assign(socket, default_branch_form: to_form(changeset))}

      trimmed ->
        case Projects.update_project(selected_project, %{default_branch: trimmed}) do
          {:ok, project} ->
            socket =
              socket
              |> assign(selected_project: project)
              |> assign(default_branch_form: to_form(Project.update_changeset(project, %{})))
              |> push_event("close-modal", %{id: "default-branch-modal"})
              |> put_flash(:info, dgettext("dashboard_projects", "Default branch updated."))

            {:noreply, socket}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign(socket, default_branch_form: to_form(changeset))}
        end
    end
  end

  def handle_event("close_default_branch_modal", _params, socket) do
    socket =
      socket
      |> push_event("close-modal", %{id: "default-branch-modal"})
      |> assign(default_branch_form: to_form(Project.update_changeset(socket.assigns.selected_project, %{})))

    {:noreply, socket}
  end

  def handle_event(
        "update_preview_access",
        %{"visibility" => visibility},
        %{assigns: %{selected_project: selected_project}} = socket
      ) do
    {:ok, updated_project} =
      Projects.update_project(selected_project, %{default_previews_visibility: String.to_existing_atom(visibility)})

    socket = assign(socket, selected_project: updated_project)
    {:noreply, socket}
  end

  def handle_event("validate_logo", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("cancel_logo_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :logo, ref)}
  end

  def handle_event("upload_logo", _params, socket) do
    %{selected_project: project} = socket.assigns

    result =
      consume_uploaded_entries(socket, :logo, fn %{path: path}, entry ->
        content_type = resolve_logo_content_type(entry)

        with {:ok, binary} <- File.read(path),
             {:ok, updated} <- Projects.set_project_logo(project, binary, content_type) do
          {:ok, {:ok, updated}}
        else
          {:error, reason} -> {:ok, {:error, reason}}
        end
      end)

    case result do
      [{:ok, updated}] ->
        socket =
          socket
          |> assign(:selected_project, updated)
          |> put_flash(:info, dgettext("dashboard_projects", "Logo updated."))

        {:noreply, socket}

      [{:error, :unsupported_logo_content_type}] ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("dashboard_projects", "Logo must be a PNG, JPEG, or WebP image.")
         )}

      [{:error, _reason}] ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("dashboard_projects", "We couldn't save the logo. Please try again.")
         )}

      [] ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("dashboard_projects", "Select a logo before uploading.")
         )}
    end
  end

  def handle_event("remove_logo", _params, %{assigns: %{selected_project: project}} = socket) do
    case Projects.clear_project_logo(project) do
      {:ok, updated} ->
        socket =
          socket
          |> assign(:selected_project, updated)
          |> put_flash(:info, dgettext("dashboard_projects", "Logo removed."))

        {:noreply, socket}

      {:error, _} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("dashboard_projects", "We couldn't remove the logo. Please try again.")
         )}
    end
  end

  def logo_upload_error_message(:too_large) do
    dgettext("dashboard_projects", "Logo must be 2 MB or smaller.")
  end

  def logo_upload_error_message(:not_accepted) do
    dgettext("dashboard_projects", "Logo must be a PNG, JPEG, or WebP image.")
  end

  def logo_upload_error_message(:too_many_files) do
    dgettext("dashboard_projects", "Only one logo can be uploaded at a time.")
  end

  def logo_upload_error_message(_), do: dgettext("dashboard_projects", "The selected file couldn't be uploaded.")

  # Prefer the browser-reported MIME, but fall back to the extension because
  # some browsers report an empty or non-canonical type (e.g. "image/jpg").
  defp resolve_logo_content_type(entry) do
    if entry.client_type in Projects.logo_allowed_content_types() do
      entry.client_type
    else
      case entry.client_name |> Path.extname() |> String.downcase() do
        ".png" -> "image/png"
        ".jpg" -> "image/jpeg"
        ".jpeg" -> "image/jpeg"
        ".webp" -> "image/webp"
        _ -> entry.client_type
      end
    end
  end
end
