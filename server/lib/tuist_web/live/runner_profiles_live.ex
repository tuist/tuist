defmodule TuistWeb.RunnerProfilesLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection

  alias Tuist.Authorization
  alias Tuist.FeatureFlags
  alias Tuist.Runners.Profile
  alias Tuist.Runners.Profiles

  @impl true
  def mount(_params, _session, %{assigns: %{selected_account: selected_account, current_user: current_user}} = socket) do
    if Authorization.authorize(:projects_read, current_user, selected_account) != :ok or
         not FeatureFlags.runners_enabled?(selected_account) do
      raise TuistWeb.Errors.NotFoundError,
            dgettext("dashboard_runners", "The page you are looking for doesn't exist or has been moved.")
    end

    {:ok,
     socket
     |> assign(
       :head_title,
       "#{dgettext("dashboard_runners", "Profiles")} · #{selected_account.name} · Tuist"
     )
     |> assign_profiles()}
  end

  @impl true
  def handle_params(_params, uri, socket) do
    {:noreply, assign(socket, :uri, URI.parse(uri))}
  end

  @impl true
  def handle_event("delete-profile", %{"id" => id}, %{assigns: %{selected_account: account}} = socket) do
    case account |> Profiles.list_for_account() |> Enum.find(&(to_string(&1.id) == id)) do
      nil ->
        {:noreply, socket}

      profile ->
        {:ok, _} = Profiles.delete(profile)

        {:noreply,
         socket
         |> assign_profiles()
         |> put_flash(
           :info,
           dgettext("dashboard_runners", "Profile %{name} deleted.", name: profile.name)
         )}
    end
  end

  defp assign_profiles(%{assigns: %{selected_account: account}} = socket) do
    profiles = Profiles.list_for_account(account)

    assign(socket,
      profiles: profiles,
      max_profiles_reached?: length(profiles) >= Profiles.max_per_account()
    )
  end

  @doc """
  The `runs-on:` snippet to show in the table — `tuist-<name>`.
  Stable for the profile's lifetime since name is immutable.
  """
  def dispatch_snippet(%Profile{} = profile), do: Profile.dispatch_label(profile)

  @doc """
  Path to the create / edit form for `name`. Used by the page header
  CTA and the edit action on each row.
  """
  def profile_form_path(account_name, name) when is_binary(account_name) and is_binary(name) do
    "/#{account_name}/runners/profiles/#{name}"
  end
end
