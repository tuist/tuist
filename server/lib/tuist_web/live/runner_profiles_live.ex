defmodule TuistWeb.RunnerProfilesLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Authorization
  alias Tuist.FeatureFlags
  alias Tuist.Runners.Catalog
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.Profile
  alias Tuist.Runners.Profiles

  @modal_id "runner-profile-modal"

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
     |> assign(:catalog, Catalog.list())
     |> assign(:modal_id, @modal_id)
     |> assign_profiles()
     |> reset_form()}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("open_create_modal", _params, socket) do
    {:noreply, reset_form(socket)}
  end

  def handle_event("open_edit_modal", %{"id" => id}, %{assigns: %{selected_account: account}} = socket) do
    case account |> Profiles.list_for_account() |> Enum.find(&(to_string(&1.id) == id)) do
      nil ->
        {:noreply, socket}

      %Profile{} = profile ->
        {:noreply,
         socket
         |> assign(:form_mode, {:edit, profile.id})
         |> assign(:form_name, profile.name)
         |> assign(:form_vcpus, profile.vcpus)
         |> assign(:form_memory_gb, profile.memory_gb)
         |> assign(:form_error, nil)
         |> push_event("open-modal", %{id: @modal_id})}
    end
  end

  def handle_event("dismiss_modal", _params, socket) do
    {:noreply, reset_form(socket)}
  end

  def handle_event("update_form_name", %{"value" => name}, socket) do
    {:noreply, socket |> assign(:form_name, name) |> assign(:form_error, nil)}
  end

  def handle_event("select_shape", params, socket) do
    case params |> shape_key_from_params() |> parse_shape_key() do
      {vcpus, memory_gb} ->
        {:noreply,
         socket
         |> assign(:form_vcpus, vcpus)
         |> assign(:form_memory_gb, memory_gb)
         |> assign(:form_error, nil)}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("save_profile", _params, %{assigns: assigns} = socket) do
    attrs = %{
      "name" => assigns.form_name,
      "vcpus" => assigns.form_vcpus,
      "memory_gb" => assigns.form_memory_gb
    }

    handle_save_result(socket, assigns.form_mode, save_profile(assigns, attrs))
  end

  def handle_event("delete_profile", %{"id" => id}, %{assigns: %{selected_account: account}} = socket) do
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

  defp save_profile(%{form_mode: :new, selected_account: account}, attrs), do: Profiles.create(account, attrs)

  defp save_profile(%{form_mode: {:edit, id}, selected_account: account}, attrs) do
    case account |> Profiles.list_for_account() |> Enum.find(&(&1.id == id)) do
      nil -> {:error, :not_found}
      profile -> Profiles.update(profile, attrs)
    end
  end

  defp handle_save_result(socket, form_mode, {:ok, profile}) do
    {:noreply,
     socket
     |> assign_profiles()
     |> reset_form()
     |> put_flash(:info, save_success_flash(form_mode, profile))}
  end

  defp handle_save_result(socket, _form_mode, {:error, :max_profiles_reached}) do
    {:noreply,
     assign(
       socket,
       :form_error,
       dgettext("dashboard_runners", "Profile limit reached (%{max}).", max: Profiles.max_per_account())
     )}
  end

  defp handle_save_result(socket, _form_mode, {:error, :not_found}), do: {:noreply, reset_form(socket)}

  defp handle_save_result(socket, _form_mode, {:error, %Ecto.Changeset{} = changeset}),
    do: {:noreply, assign(socket, :form_error, humanize_changeset_errors(changeset))}

  defp save_success_flash(:new, profile),
    do: dgettext("dashboard_runners", "Profile %{name} created.", name: profile.name)

  defp save_success_flash({:edit, _}, profile),
    do: dgettext("dashboard_runners", "Profile %{name} updated.", name: profile.name)

  defp assign_profiles(%{assigns: %{selected_account: account}} = socket) do
    profiles = Profiles.list_for_account(account)

    assign(socket,
      profiles: profiles,
      last_used: Jobs.last_used_at_by_dispatch_label(account.id),
      max_profiles_reached?: length(profiles) >= Profiles.max_per_account()
    )
  end

  defp reset_form(%{assigns: %{catalog: catalog}} = socket) do
    default_shape = Enum.find(catalog, & &1.default?) || List.first(catalog)

    socket
    |> assign(:form_mode, :new)
    |> assign(:form_name, "")
    |> assign(:form_vcpus, default_shape && default_shape.vcpus)
    |> assign(:form_memory_gb, default_shape && default_shape.memory_gb)
    |> assign(:form_error, nil)
  end

  # Noora's <.select> fires on_value_change with `%{"value" => [key]}`;
  # accept the bare-string and `%{"data" => key}` shapes too so tests
  # and any future trigger can drive the same handler.
  defp shape_key_from_params(%{"value" => [key | _]}), do: key
  defp shape_key_from_params(%{"value" => key}) when is_binary(key), do: key
  defp shape_key_from_params(%{"data" => key}) when is_binary(key), do: key
  defp shape_key_from_params(key) when is_binary(key), do: key
  defp shape_key_from_params(_), do: nil

  defp parse_shape_key(key) when is_binary(key) do
    case Regex.run(~r/^(\d+)vcpu-(\d+)gb$/, key) do
      [_, vcpus, memory_gb] -> {String.to_integer(vcpus), String.to_integer(memory_gb)}
      _ -> :error
    end
  end

  defp parse_shape_key(_), do: :error

  @doc """
  The `runs-on:` snippet to show in the table — `tuist-<name>`.
  """
  def dispatch_snippet(%Profile{} = profile), do: Profile.dispatch_label(profile)

  @doc """
  Relative "last used" string for a profile, from the precomputed
  `last_used` map (label => DateTime). Renders "Never" when the
  profile has no jobs yet.
  """
  def last_used_label(last_used, %Profile{} = profile) when is_map(last_used) do
    case Map.get(last_used, Profile.dispatch_label(profile)) do
      %DateTime{} = ts -> Tuist.Utilities.DateFormatter.from_now(ts)
      _ -> dgettext("dashboard_runners", "Never")
    end
  end

  @doc """
  Platform a profile runs on. Linux-only in v1 — macOS profiles are a
  future addition, at which point this reads off the shape/catalog.
  """
  def platform_label(%Profile{}), do: "Linux"

  @doc """
  Shape key in the catalog format used as the dropdown value.
  """
  def shape_key(vcpus, memory_gb) when is_integer(vcpus) and is_integer(memory_gb), do: "#{vcpus}vcpu-#{memory_gb}gb"

  def shape_key(_, _), do: ""

  @doc """
  Human-readable shape label, e.g. `4 vCPU, 16 GB RAM`.
  """
  def shape_label(vcpus, memory_gb) when is_integer(vcpus) and is_integer(memory_gb),
    do: "#{vcpus} vCPU, #{memory_gb} GB RAM"

  def shape_label(_, _), do: ""

  defp humanize_changeset_errors(%Ecto.Changeset{errors: errors}) do
    Enum.map_join(errors, "; ", fn {field, {msg, opts}} ->
      msg = Enum.reduce(opts, msg, fn {key, value}, acc -> String.replace(acc, "%{#{key}}", to_string(value)) end)
      "#{field}: #{msg}"
    end)
  end
end
