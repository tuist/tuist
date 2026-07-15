defmodule TuistWeb.AccountTokensLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import Noora.CheckboxControl
  import Phoenix.Component

  alias Tuist.Accounts
  alias Tuist.Accounts.AccountToken
  alias Tuist.Authorization
  alias Tuist.Projects
  alias Tuist.Utilities.DateFormatter

  @default_scopes ["ci"]

  @valid_scopes AccountToken.valid_scopes()

  @impl true
  def mount(_params, _uri, %{assigns: %{selected_account: selected_account, current_user: current_user}} = socket) do
    if Authorization.authorize(:account_token_read, current_user, selected_account) != :ok do
      raise TuistWeb.Errors.UnauthorizedError,
            dgettext("dashboard_account", "You are not authorized to perform this action.")
    end

    account_tokens = list_account_tokens(selected_account)

    socket =
      socket
      |> assign(:account_tokens, account_tokens)
      |> assign(:selected_account_token, select_account_token(account_tokens, nil))
      |> assign(:selected_scopes, @default_scopes)
      |> assign(:new_account_token_plaintext, nil)
      |> assign(:new_account_token_form, new_account_token_form())
      |> assign(:flash_message, nil)
      |> assign(
        :can_create_tokens?,
        Authorization.authorize(:account_token_create, current_user, selected_account) == :ok
      )
      |> assign(
        :can_delete_tokens?,
        Authorization.authorize(:account_token_delete, current_user, selected_account) == :ok
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

  def handle_event("create_account_token", %{"account_token" => params}, socket) do
    with :ok <- ensure_can_create(socket),
         {:ok, name} <- token_name(params),
         {:ok, expires_at} <- expires_at(params),
         {:ok, scopes} <- token_scopes(socket),
         project_handles = project_handles(params),
         {:ok, projects} <-
           Projects.get_projects_by_handles_for_account(
             socket.assigns.selected_account,
             project_handles
           ),
         {:ok, {token_record, plaintext}} <-
           Accounts.create_account_token(%{
             account: socket.assigns.selected_account,
             scopes: scopes,
             created_by_account: socket.assigns.current_user.account,
             name: name,
             expires_at: expires_at,
             all_projects: project_handles == [],
             project_ids: Enum.map(projects, & &1.id)
           }) do
      account_tokens = list_account_tokens(socket.assigns.selected_account)

      {:noreply,
       socket
       |> assign(:account_tokens, account_tokens)
       |> assign(:selected_account_token, select_account_token(account_tokens, token_record.id))
       |> assign(:new_account_token_plaintext, plaintext)
       |> assign(:new_account_token_form, new_account_token_form())
       |> assign(:selected_scopes, @default_scopes)
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

      {:error, :invalid_expiration} ->
        {:noreply,
         assign(
           socket,
           :flash_message,
           {"error", dgettext("dashboard_account", "Expiration must use a duration like 30d, 6m, or 1y.")}
         )}

      {:error, :not_found, handle} ->
        {:noreply,
         assign(
           socket,
           :flash_message,
           {"error", dgettext("dashboard_account", "Project %{handle} was not found in this account.", handle: handle)}
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, :flash_message, {"error", format_changeset_errors(changeset)})}
    end
  end

  def handle_event("select_account_token", %{"id" => id}, socket) do
    {:noreply, assign(socket, :selected_account_token, select_account_token(socket.assigns.account_tokens, id))}
  end

  def handle_event("dismiss_account_token", _params, socket) do
    {:noreply,
     socket
     |> assign(:new_account_token_plaintext, nil)
     |> assign(:new_account_token_form, new_account_token_form())
     |> assign(:selected_scopes, @default_scopes)
     |> push_event("close-modal", %{id: "create-account-token-modal"})}
  end

  def handle_event("account_token_modal_open_change", %{"open" => false}, socket) do
    {:noreply,
     socket
     |> assign(:new_account_token_plaintext, nil)
     |> assign(:new_account_token_form, new_account_token_form())
     |> assign(:selected_scopes, @default_scopes)}
  end

  def handle_event("account_token_modal_open_change", _params, socket), do: {:noreply, socket}

  def handle_event("revoke_account_token", %{"name" => name}, socket) do
    with :ok <- ensure_can_delete(socket),
         {:ok, token} <- Accounts.get_account_token_by_name(socket.assigns.selected_account, name),
         {:ok, _token} <- Accounts.delete_account_token(token) do
      deleted_token_id = token.id

      selected_token_id =
        case socket.assigns.selected_account_token do
          %AccountToken{id: ^deleted_token_id} -> nil
          %AccountToken{id: id} -> id
          _ -> nil
        end

      account_tokens = list_account_tokens(socket.assigns.selected_account)

      {:noreply,
       socket
       |> assign(:account_tokens, account_tokens)
       |> assign(:selected_account_token, select_account_token(account_tokens, selected_token_id))
       |> assign(:flash_message, nil)}
    else
      {:error, :forbidden} ->
        {:noreply,
         assign(
           socket,
           :flash_message,
           {"error", dgettext("dashboard_account", "You are not authorized to revoke account tokens.")}
         )}

      {:error, :not_found} ->
        {:noreply, assign(socket, :flash_message, {"error", dgettext("dashboard_account", "Token not found.")})}
    end
  end

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

  defp select_account_token([], _token_id), do: nil

  defp select_account_token(tokens, nil), do: List.first(tokens)

  defp select_account_token(tokens, token_id) do
    Enum.find(tokens, &(&1.id == token_id)) || List.first(tokens)
  end

  defp ensure_can_create(%{assigns: %{can_create_tokens?: true}}), do: :ok
  defp ensure_can_create(_socket), do: {:error, :forbidden}

  defp ensure_can_delete(%{assigns: %{can_delete_tokens?: true}}), do: :ok
  defp ensure_can_delete(_socket), do: {:error, :forbidden}

  defp token_name(params) do
    case params |> Map.get("name", "") |> String.trim() do
      "" -> {:error, :missing_name}
      name -> {:ok, name}
    end
  end

  defp token_scopes(%{assigns: %{selected_scopes: []}}), do: {:error, :missing_scopes}
  defp token_scopes(%{assigns: %{selected_scopes: scopes}}), do: {:ok, scopes}

  defp project_handles(params) do
    params
    |> Map.get("project_handles", "")
    |> String.split([",", "\n", " "], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

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
    to_form(%{"name" => "", "expires" => "", "project_handles" => ""}, as: "account_token")
  end

  defp scope_options do
    [
      %{
        label: dgettext("dashboard_account", "Presets"),
        scopes: [
          %{
            scope: "ci",
            label: dgettext("dashboard_account", "CI"),
            description:
              dgettext(
                "dashboard_account",
                "Cache writes, previews, bundles, tests, builds, and runs for CI jobs."
              )
          },
          %{
            scope: "mcp",
            label: dgettext("dashboard_account", "MCP"),
            description:
              dgettext(
                "dashboard_account",
                "Read project metadata, cache, previews, bundles, tests, builds, and runs."
              )
          }
        ]
      },
      %{
        label: dgettext("dashboard_account", "Account"),
        scopes: [
          %{
            scope: "account:cache:read",
            label: dgettext("dashboard_account", "Cache read"),
            description: dgettext("dashboard_account", "Read account-level cache entries.")
          },
          %{
            scope: "account:cache:write",
            label: dgettext("dashboard_account", "Cache write"),
            description: dgettext("dashboard_account", "Read and write account-level cache entries.")
          },
          %{
            scope: "account:members:read",
            label: dgettext("dashboard_account", "Members read"),
            description: dgettext("dashboard_account", "Read organization members and invitations.")
          },
          %{
            scope: "account:members:write",
            label: dgettext("dashboard_account", "Members write"),
            description: dgettext("dashboard_account", "Manage organization members and invitations.")
          },
          %{
            scope: "account:registry:read",
            label: dgettext("dashboard_account", "Registry read"),
            description: dgettext("dashboard_account", "Read packages from the account registry.")
          },
          %{
            scope: "account:registry:write",
            label: dgettext("dashboard_account", "Registry write"),
            description: dgettext("dashboard_account", "Publish packages to the account registry.")
          },
          %{
            scope: "account:scim:write",
            label: dgettext("dashboard_account", "SCIM write"),
            description: dgettext("dashboard_account", "Provision organization members through SCIM.")
          }
        ]
      },
      %{
        label: dgettext("dashboard_account", "Project"),
        scopes: [
          %{
            scope: "project:admin:read",
            label: dgettext("dashboard_account", "Admin read"),
            description: dgettext("dashboard_account", "Read project administration data.")
          },
          %{
            scope: "project:admin:write",
            label: dgettext("dashboard_account", "Admin write"),
            description: dgettext("dashboard_account", "Manage project administration data.")
          },
          %{
            scope: "project:cache:read",
            label: dgettext("dashboard_account", "Cache read"),
            description: dgettext("dashboard_account", "Read project cache entries.")
          },
          %{
            scope: "project:cache:write",
            label: dgettext("dashboard_account", "Cache write"),
            description: dgettext("dashboard_account", "Read and write project cache entries.")
          },
          %{
            scope: "project:previews:read",
            label: dgettext("dashboard_account", "Previews read"),
            description: dgettext("dashboard_account", "Read previews.")
          },
          %{
            scope: "project:previews:write",
            label: dgettext("dashboard_account", "Previews write"),
            description: dgettext("dashboard_account", "Create and manage previews.")
          },
          %{
            scope: "project:bundles:read",
            label: dgettext("dashboard_account", "Bundles read"),
            description: dgettext("dashboard_account", "Read bundle analytics.")
          },
          %{
            scope: "project:bundles:write",
            label: dgettext("dashboard_account", "Bundles write"),
            description: dgettext("dashboard_account", "Upload and manage bundle data.")
          },
          %{
            scope: "project:tests:read",
            label: dgettext("dashboard_account", "Tests read"),
            description: dgettext("dashboard_account", "Read test analytics.")
          },
          %{
            scope: "project:tests:write",
            label: dgettext("dashboard_account", "Tests write"),
            description: dgettext("dashboard_account", "Upload and manage test data.")
          },
          %{
            scope: "project:builds:read",
            label: dgettext("dashboard_account", "Builds read"),
            description: dgettext("dashboard_account", "Read build analytics.")
          },
          %{
            scope: "project:builds:write",
            label: dgettext("dashboard_account", "Builds write"),
            description: dgettext("dashboard_account", "Upload and manage build data.")
          },
          %{
            scope: "project:runs:read",
            label: dgettext("dashboard_account", "Runs read"),
            description: dgettext("dashboard_account", "Read runs.")
          },
          %{
            scope: "project:runs:write",
            label: dgettext("dashboard_account", "Runs write"),
            description: dgettext("dashboard_account", "Create and manage runs.")
          }
        ]
      }
    ]
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

  defp scopes_label(scopes), do: Enum.join(scopes, ", ")

  defp selected_scope_groups(scopes) do
    scope_options()
    |> Enum.map(fn group ->
      %{group | scopes: Enum.filter(group.scopes, &(&1.scope in scopes))}
    end)
    |> Enum.reject(&Enum.empty?(&1.scopes))
  end

  defp project_handle(account, project), do: "#{account.name}/#{project.name}"

  defp account_token_hint(%AccountToken{scopes: scopes, token_last_four: token_last_four}) do
    prefix =
      if AccountToken.scim_scope() in scopes do
        "tuist_scim_"
      else
        "tuist_"
      end

    case token_last_four do
      value when is_binary(value) and value != "" -> prefix <> String.duplicate("•", 10) <> value
      _ -> prefix <> String.duplicate("•", 14)
    end
  end

  defp expires_label(%AccountToken{expires_at: nil}), do: dgettext("dashboard_account", "Never")

  defp expires_label(%AccountToken{expires_at: expires_at}), do: DateFormatter.from_now(expires_at)

  defp last_used_label(%AccountToken{last_used_at: nil}), do: dgettext("dashboard_account", "Never")

  defp last_used_label(%AccountToken{last_used_at: last_used_at}), do: DateFormatter.from_now(last_used_at)

  defp created_label(%AccountToken{inserted_at: inserted_at}), do: DateFormatter.from_now(inserted_at)
end
