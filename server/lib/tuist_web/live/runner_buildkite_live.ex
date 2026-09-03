defmodule TuistWeb.RunnerBuildkiteLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Authorization
  alias Tuist.FeatureFlags
  alias Tuist.Runners.Buildkite
  alias Tuist.Runners.Profile
  alias Tuist.Runners.Profiles

  @impl true
  def mount(_params, _session, %{assigns: %{selected_account: selected_account, current_user: current_user}} = socket) do
    if Authorization.authorize(:account_update, current_user, selected_account) != :ok or
         not FeatureFlags.runners_enabled?(selected_account) do
      raise TuistWeb.Errors.NotFoundError,
            dgettext("dashboard_runners", "The page you are looking for doesn't exist or has been moved.")
    end

    {:ok,
     socket
     |> assign(
       :head_title,
       "#{dgettext("dashboard_runners", "Buildkite")} · #{selected_account.name} · Tuist"
     )
     |> assign(:queue_keys, queue_keys(selected_account))
     |> assign(:form_error, nil)
     |> assign_installation()}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("connect", params, %{assigns: %{selected_account: account}} = socket) do
    attrs = %{
      organization_slug: String.trim(Map.get(params, "organization_slug", "")),
      cluster_name: String.trim(Map.get(params, "cluster_name", "")),
      stack_key: stack_key(account, params),
      agent_token: String.trim(Map.get(params, "agent_token", ""))
    }

    case Buildkite.upsert_installation(account.id, attrs) do
      {:ok, _installation} ->
        {:noreply, socket |> assign(:form_error, nil) |> assign_installation()}

      {:error, changeset} ->
        {:noreply, assign(socket, :form_error, first_error(changeset))}
    end
  end

  def handle_event("disconnect", _params, %{assigns: %{selected_account: account}} = socket) do
    :ok = Buildkite.delete_installation(account.id)
    {:noreply, socket |> assign(:form_error, nil) |> assign_installation()}
  end

  # The stack key identifies this controller to Buildkite and scopes its
  # reservations, so it has to be stable for the life of the connection
  # and unique across Tuist. Derived from the account rather than asked
  # for: it is an implementation detail of the integration, and a
  # customer choosing one that collides with another account's would
  # hand them each other's reservations.
  defp stack_key(account, params) do
    case Map.get(params, "stack_key") do
      key when is_binary(key) and key != "" -> key
      _ -> "tuist-#{account.id}"
    end
  end

  defp assign_installation(%{assigns: %{selected_account: account}} = socket) do
    assign(socket, :installation, Buildkite.get_installation(account.id))
  end

  defp queue_keys(account) do
    account |> Profiles.list_for_account() |> Enum.map(&Profile.dispatch_label/1)
  end

  defp first_error(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Regex.replace(~r/%\{(\w+)\}/, message, fn _whole, key ->
        opts |> Keyword.get(String.to_existing_atom(key), "") |> to_string()
      end)
    end)
    |> Enum.flat_map(fn {field, messages} -> Enum.map(messages, &"#{field} #{&1}") end)
    |> List.first()
  end
end
