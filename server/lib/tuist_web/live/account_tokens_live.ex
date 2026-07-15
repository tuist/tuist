defmodule TuistWeb.AccountTokensLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import Noora.CheckboxControl
  import Phoenix.Component
  import TuistWeb.AccountTokenHelpers

  alias Tuist.Accounts
  alias Tuist.Accounts.AccountToken
  alias Tuist.Authorization
  alias Tuist.Projects

  @default_scopes ["ci"]

  @valid_scopes AccountToken.valid_scopes()

  @impl true
  def mount(_params, _uri, %{assigns: %{selected_account: selected_account, current_user: current_user}} = socket) do
    if Authorization.authorize(:account_token_read, current_user, selected_account) != :ok do
      raise TuistWeb.Errors.UnauthorizedError,
            dgettext("dashboard_account", "You are not authorized to perform this action.")
    end

    account_tokens = list_account_tokens(selected_account)
    available_projects = list_account_projects(selected_account)

    socket =
      socket
      |> assign(:account_tokens, account_tokens)
      |> assign(:available_projects, available_projects)
      |> assign(:selected_project_ids, project_ids(available_projects))
      |> assign(:selected_scopes, @default_scopes)
      |> assign(:new_account_token_plaintext, nil)
      |> assign(:new_account_token_form, new_account_token_form())
      |> assign(:flash_message, nil)
      |> assign(
        :can_create_tokens?,
        Authorization.authorize(:account_token_create, current_user, selected_account) == :ok
      )
      |> assign(:scope_options, scope_options())
      |> assign(:head_title, "#{dgettext("dashboard_account", "Tokens")} · #{selected_account.name} · Tuist")

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_token_scope", %{"scope" => scope}, socket) when scope in @valid_scopes do
    selected_scopes =
      if scope in socket.assigns.selected_scopes do
        List.delete(socket.assigns.selected_scopes, scope)
      else
        [scope | socket.assigns.selected_scopes]
      end

    {:noreply, assign(socket, :selected_scopes, Enum.sort(selected_scopes))}
  end

  def handle_event("toggle_token_scope", _params, socket), do: {:noreply, socket}

  def handle_event("toggle_all_project_access_projects", _params, socket) do
    selected_project_ids =
      if all_project_access_projects_selected?(socket.assigns.available_projects, socket.assigns.selected_project_ids) do
        []
      else
        project_ids(socket.assigns.available_projects)
      end

    {:noreply, assign(socket, :selected_project_ids, selected_project_ids)}
  end

  def handle_event("toggle_project_access_project", %{"project-id" => project_id}, socket) do
    with {project_id, ""} <- Integer.parse(project_id),
         true <- Enum.any?(socket.assigns.available_projects, &(&1.id == project_id)) do
      selected_project_ids =
        if project_id in socket.assigns.selected_project_ids do
          List.delete(socket.assigns.selected_project_ids, project_id)
        else
          [project_id | socket.assigns.selected_project_ids]
        end

      {:noreply, assign(socket, :selected_project_ids, Enum.sort(selected_project_ids))}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("toggle_project_access_project", _params, socket), do: {:noreply, socket}

  def handle_event("create_account_token", %{"account_token" => params}, socket) do
    with :ok <- ensure_can_create(socket),
         {:ok, name} <- token_name(params),
         {:ok, expires_at} <- expires_at(params),
         {:ok, scopes} <- token_scopes(socket),
         {:ok, project_access} <- token_project_access(socket),
         {:ok, {token_record, plaintext}} <-
           Accounts.create_account_token(%{
             account: socket.assigns.selected_account,
             scopes: scopes,
             created_by_account: socket.assigns.current_user.account,
             name: name,
             expires_at: expires_at,
             all_projects: project_access.all_projects,
             project_ids: project_access.project_ids
           }) do
      account_tokens = list_account_tokens(socket.assigns.selected_account)

      {:noreply,
       socket
       |> assign(:account_tokens, account_tokens)
       |> assign(:new_account_token_plaintext, plaintext)
       |> assign(:new_account_token_form, new_account_token_form())
       |> assign(:selected_scopes, @default_scopes)
       |> assign(:selected_project_ids, project_ids(socket.assigns.available_projects))
       |> assign(:flash_message, nil)
       |> put_flash(
         :info,
         dgettext("dashboard_account", "%{name} was created.", name: token_record.name)
       )}
    else
      {:error, :forbidden} ->
        {:noreply,
         assign(
           socket,
           :flash_message,
           {"error", dgettext("dashboard_account", "You are not authorized to create account tokens.")}
         )}

      {:error, :missing_name} ->
        {:noreply, assign(socket, :flash_message, {"error", dgettext("dashboard_account", "Token name is required.")})}

      {:error, :missing_scopes} ->
        {:noreply,
         assign(
           socket,
           :flash_message,
           {"error", dgettext("dashboard_account", "Select at least one scope.")}
         )}

      {:error, :missing_projects} ->
        {:noreply,
         assign(
           socket,
           :flash_message,
           {"error", dgettext("dashboard_account", "Select at least one project or select all projects.")}
         )}

      {:error, :invalid_expiration} ->
        {:noreply,
         assign(
           socket,
           :flash_message,
           {"error", dgettext("dashboard_account", "Expiration must use a duration like 30d, 6m, or 1y.")}
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, :flash_message, {"error", format_changeset_errors(changeset)})}
    end
  end

  def handle_event("dismiss_account_token", _params, socket) do
    {:noreply,
     socket
     |> assign(:new_account_token_plaintext, nil)
     |> assign(:new_account_token_form, new_account_token_form())
     |> assign(:selected_scopes, @default_scopes)
     |> assign(:selected_project_ids, project_ids(socket.assigns.available_projects))
     |> push_event("close-modal", %{id: "create-account-token-modal"})}
  end

  def handle_event("account_token_modal_open_change", %{"open" => false}, socket) do
    {:noreply,
     socket
     |> assign(:new_account_token_plaintext, nil)
     |> assign(:new_account_token_form, new_account_token_form())
     |> assign(:selected_scopes, @default_scopes)
     |> assign(:selected_project_ids, project_ids(socket.assigns.available_projects))}
  end

  def handle_event("account_token_modal_open_change", _params, socket), do: {:noreply, socket}

  defp list_account_tokens(account) do
    {tokens, _meta} =
      Accounts.list_account_tokens(account, %{
        order_by: [:inserted_at],
        order_directions: [:desc],
        page: 1,
        page_size: 100
      })

    tokens
  end

  defp list_account_projects(account) do
    {projects, _meta} =
      Projects.list_projects(%{
        filters: [%{field: :account_id, op: :==, value: account.id}],
        order_by: [:name],
        order_directions: [:asc],
        page: 1,
        page_size: 500
      })

    projects
  end

  defp ensure_can_create(%{assigns: %{can_create_tokens?: true}}), do: :ok
  defp ensure_can_create(_socket), do: {:error, :forbidden}

  defp token_name(params) do
    case params |> Map.get("name", "") |> String.trim() do
      "" -> {:error, :missing_name}
      name -> {:ok, name}
    end
  end

  defp token_scopes(%{assigns: %{selected_scopes: []}}), do: {:error, :missing_scopes}
  defp token_scopes(%{assigns: %{selected_scopes: scopes}}), do: {:ok, scopes}

  defp token_project_access(%{assigns: %{available_projects: [], selected_project_ids: []}}) do
    {:ok, %{all_projects: true, project_ids: []}}
  end

  defp token_project_access(%{assigns: %{selected_project_ids: []}}) do
    {:error, :missing_projects}
  end

  defp token_project_access(%{assigns: %{available_projects: available_projects, selected_project_ids: project_ids}}) do
    if all_project_access_projects_selected?(available_projects, project_ids) do
      {:ok, %{all_projects: true, project_ids: []}}
    else
      {:ok, %{all_projects: false, project_ids: project_ids}}
    end
  end

  defp all_project_access_projects_selected?(available_projects, selected_project_ids) do
    available_project_ids = project_ids(available_projects)
    available_project_ids != [] and Enum.all?(available_project_ids, &(&1 in selected_project_ids))
  end

  defp project_access_projects_partially_selected?(available_projects, selected_project_ids) do
    available_project_ids = project_ids(available_projects)
    selected_count = Enum.count(available_project_ids, &(&1 in selected_project_ids))
    selected_count > 0 and selected_count < length(available_project_ids)
  end

  defp project_ids(projects), do: Enum.map(projects, & &1.id)

  defp expires_at(params) do
    params
    |> Map.get("expires", "")
    |> String.trim()
    |> case do
      "" -> {:ok, nil}
      duration -> parse_expires_duration(duration)
    end
  end

  defp parse_expires_duration(duration) do
    case Regex.run(~r/^(\d+)([dmy])$/i, duration) do
      [_, amount, unit] ->
        amount = String.to_integer(amount)

        {:ok,
         DateTime.utc_now()
         |> shift_expiration(String.downcase(unit), amount)
         |> DateTime.truncate(:second)}

      _ ->
        {:error, :invalid_expiration}
    end
  end

  defp shift_expiration(datetime, "d", days), do: Timex.shift(datetime, days: days)
  defp shift_expiration(datetime, "m", months), do: Timex.shift(datetime, months: months)
  defp shift_expiration(datetime, "y", years), do: Timex.shift(datetime, years: years)

  defp new_account_token_form do
    to_form(%{"name" => "", "expires" => ""}, as: "account_token")
  end

  defp format_changeset_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join("; ", fn {field, errors} ->
      "#{field}: #{Enum.join(errors, ", ")}"
    end)
  end
end
