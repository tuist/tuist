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
  @delete_modal_id "runner-profile-delete-modal"

  @impl true
  def mount(_params, _session, %{assigns: %{selected_account: selected_account, current_user: current_user}} = socket) do
    # Create / edit / delete rows affect every workflow on the account, so
    # the page is gated on `:runners_update` (admin-only for users).
    # Read-only sibling views use `:runners_read` because they only
    # surface state.
    if Authorization.authorize(:runners_update, current_user, selected_account) != :ok or
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
     |> assign(:catalog, Catalog.shapes(:linux))
     |> assign(:macos_catalog, Catalog.shapes(:macos))
     |> assign(:xcode_catalog, Catalog.xcode_versions())
     |> assign(:os_catalog, Catalog.os_versions())
     |> assign(:modal_id, @modal_id)
     |> assign(:delete_modal_id, @delete_modal_id)
     |> assign(:deleting_profile, nil)
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
         |> assign(:form_platform, Atom.to_string(profile.platform))
         |> assign(:form_vcpus, profile.vcpus)
         |> assign(:form_memory_gb, profile.memory_gb)
         |> assign(:form_xcode_version, profile.xcode_version)
         |> assign(:form_os_version, profile.os_version || default_os_version(socket.assigns.os_catalog, profile))
         |> assign(:form_cache_writer_all_branches, profile.cache_writer_all_branches)
         |> assign(:form_cache_writer_default_branch, profile.cache_writer_default_branch)
         |> assign(:form_cache_writer_branches, profile.cache_writer_branches || [])
         |> assign(:form_cached_checkouts, profile.cached_checkouts)
         |> assign(:form_docker_cache, profile.docker_cache)
         |> assign(:form_cache_branch_value, "")
         |> assign(:form_cache_branch_error, nil)
         |> assign(:form_cache_saving_expanded, false)
         |> assign(:form_error, nil)
         |> push_event("open-modal", %{id: @modal_id})}
    end
  end

  def handle_event("dismiss_modal", _params, socket) do
    {:noreply, socket |> reset_form() |> close_modal()}
  end

  # Fired by Noora's modal hook on every open/close transition
  # (including escape + click-outside). Reset the form when it closes
  # so the next open starts clean; ignore the open transition.
  def handle_event("modal_open_changed", %{"open" => false}, socket) do
    {:noreply, reset_form(socket)}
  end

  def handle_event("modal_open_changed", _params, socket), do: {:noreply, socket}

  def handle_event("update_form_name", %{"value" => name}, socket) do
    {:noreply, socket |> assign(:form_name, name) |> assign(:form_error, nil)}
  end

  def handle_event("toggle_cache_saving_section", _params, socket) do
    {:noreply, assign(socket, :form_cache_saving_expanded, not socket.assigns.form_cache_saving_expanded)}
  end

  def handle_event("add_cache_writer_branch", %{"branch" => value}, socket) when is_binary(value) do
    branch = String.trim(value)

    cond do
      branch == "" ->
        {:noreply, socket}

      Profile.valid_cache_writer_branch?(branch) ->
        {:noreply,
         socket
         |> update(:form_cache_writer_branches, &Enum.uniq(&1 ++ [branch]))
         |> update(:form_cache_branch_input, &(&1 + 1))
         |> assign(:form_cache_branch_value, "")
         |> assign(:form_cache_branch_error, nil)}

      true ->
        {:noreply,
         socket
         |> assign(:form_cache_branch_value, value)
         |> assign(
           :form_cache_branch_error,
           dgettext("dashboard_runners", "Use a branch name, optionally with * to match any characters.")
         )}
    end
  end

  def handle_event("remove_cache_writer_branch", %{"data" => branch}, socket) do
    {:noreply,
     socket
     |> update(:form_cache_writer_branches, &List.delete(&1, branch))
     |> assign(:form_cache_branch_error, nil)}
  end

  def handle_event("toggle_cache_writer_default_branch", _params, socket) do
    {:noreply, update(socket, :form_cache_writer_default_branch, &(not &1))}
  end

  def handle_event("toggle_cached_checkouts", _params, socket) do
    {:noreply, update(socket, :form_cached_checkouts, &(not &1))}
  end

  def handle_event("toggle_docker_cache", _params, socket) do
    {:noreply, update(socket, :form_docker_cache, &(not &1))}
  end

  def handle_event("toggle_cache_writer_all_branches", _params, socket) do
    {:noreply, update(socket, :form_cache_writer_all_branches, &(not &1))}
  end

  def handle_event("select_platform", params, socket) do
    case shape_key_from_params(params) do
      platform when platform in ["linux", "macos"] ->
        # Switching platforms resets the shape + Xcode pick to the
        # new catalog's defaults so the form never carries
        # incompatible state across platforms (e.g. a Linux shape
        # selected while platform=macos).
        {:noreply, set_platform_defaults(socket, platform)}

      _ ->
        {:noreply, socket}
    end
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

  def handle_event("select_xcode_version", params, socket) do
    case shape_key_from_params(params) do
      version when is_binary(version) and version != "" ->
        {:noreply,
         socket
         |> assign(:form_xcode_version, version)
         |> assign(:form_error, nil)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("select_os_version", params, socket) do
    case shape_key_from_params(params) do
      version when is_binary(version) and version != "" ->
        {:noreply,
         socket
         |> assign(:form_os_version, version)
         |> assign(:form_error, nil)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("save_profile", _params, %{assigns: assigns} = socket) do
    attrs = %{
      "name" => assigns.form_name,
      "platform" => assigns.form_platform,
      "vcpus" => assigns.form_vcpus,
      "memory_gb" => assigns.form_memory_gb,
      "cache_writer_all_branches" => assigns.form_cache_writer_all_branches,
      "cache_writer_default_branch" => assigns.form_cache_writer_default_branch,
      "cache_writer_branches" => assigns.form_cache_writer_branches
    }

    attrs =
      case assigns.form_platform do
        "macos" -> Map.put(attrs, "xcode_version", assigns.form_xcode_version)
        _ -> Map.put(attrs, "os_version", assigns.form_os_version)
      end

    attrs =
      Map.merge(attrs, %{
        "cached_checkouts" => assigns.form_cached_checkouts,
        "docker_cache" => assigns.form_docker_cache
      })

    handle_save_result(socket, assigns.form_mode, save_profile(assigns, attrs))
  end

  # Row action: stash the target and open the Noora confirm modal.
  def handle_event("request_delete_profile", %{"id" => id}, %{assigns: %{selected_account: account}} = socket) do
    case account |> Profiles.list_for_account() |> Enum.find(&(to_string(&1.id) == id)) do
      nil ->
        {:noreply, socket}

      %Profile{} = profile ->
        {:noreply,
         socket
         |> assign(:deleting_profile, profile)
         |> push_event("open-modal", %{id: @delete_modal_id})}
    end
  end

  def handle_event("cancel_delete_profile", _params, socket) do
    {:noreply, socket |> assign(:deleting_profile, nil) |> close_delete_modal()}
  end

  def handle_event("confirm_delete_profile", _params, %{assigns: %{deleting_profile: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event(
        "confirm_delete_profile",
        _params,
        %{assigns: %{deleting_profile: %Profile{} = profile, selected_account: account}} = socket
      ) do
    socket = socket |> assign(:deleting_profile, nil) |> close_delete_modal()

    if is_nil(Profiles.get_by_name(account, profile.name)) do
      # Raced away (already deleted) — nothing to do.
      {:noreply, socket}
    else
      # Authoritative guard mirroring the hidden row action. The
      # context layer rejects `:protected` profiles (the per-account
      # auto-bootstrapped Linux default), so the `:protected` arm
      # surfaces a flash without re-fetching state.
      case Profiles.delete(profile) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign_profiles()
           |> put_flash(:info, dgettext("dashboard_runners", "Profile %{name} deleted.", name: profile.name))}

        {:error, :protected} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             dgettext("dashboard_runners", "This profile is a default and can't be deleted.")
           )}
      end
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
     |> close_modal()
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

  defp close_modal(socket), do: push_event(socket, "close-modal", %{id: @modal_id})

  defp close_delete_modal(socket), do: push_event(socket, "close-modal", %{id: @delete_modal_id})

  defp reset_form(socket) do
    socket
    |> assign(:form_mode, :new)
    |> assign(:form_name, "")
    |> assign(:form_cache_writer_all_branches, true)
    |> assign(:form_cache_writer_default_branch, true)
    |> assign(:form_cache_writer_branches, [])
    |> assign(:form_cached_checkouts, true)
    |> assign(:form_docker_cache, true)
    |> assign(:form_cache_branch_input, 0)
    |> assign(:form_cache_branch_value, "")
    |> assign(:form_cache_branch_error, nil)
    |> assign(:form_cache_saving_expanded, false)
    |> assign(:form_error, nil)
    |> set_platform_defaults("linux")
  end

  # Preselect the shape (and, on macOS, the Xcode version) from the
  # platform's catalog default. Used both on `reset_form/1` and when
  # the platform dropdown switches mid-form.
  defp set_platform_defaults(socket, "linux") do
    default_shape = pick_default(socket.assigns.catalog)

    socket
    |> assign(:form_platform, "linux")
    |> assign(:form_vcpus, default_shape && default_shape.vcpus)
    |> assign(:form_memory_gb, default_shape && default_shape.memory_gb)
    |> assign(:form_xcode_version, nil)
    |> assign(:form_os_version, default_os_version(socket.assigns.os_catalog, nil))
    |> assign(:form_error, nil)
  end

  defp set_platform_defaults(socket, "macos") do
    default_shape = pick_default(socket.assigns.macos_catalog)
    default_xcode = pick_default(socket.assigns.xcode_catalog)

    socket
    |> assign(:form_platform, "macos")
    |> assign(:form_vcpus, default_shape && default_shape.vcpus)
    |> assign(:form_memory_gb, default_shape && default_shape.memory_gb)
    |> assign(:form_xcode_version, default_xcode && default_xcode.xcode_version)
    |> assign(:form_os_version, nil)
    |> assign(:form_error, nil)
  end

  # A Linux row an older replica wrote has no OS and runs on the default.
  defp default_os_version(_os_catalog, %Profile{platform: :macos}), do: nil

  defp default_os_version(os_catalog, _profile) do
    case pick_default(os_catalog) do
      nil -> nil
      default -> default.os_version
    end
  end

  defp pick_default(list) when is_list(list) do
    Enum.find(list, & &1.default?) || List.first(list)
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
  The `runs-on:` snippet to show in the table —
  the profile's full dispatch label.
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
  Summary of the branches being edited, shown on the collapsed section.
  """
  def cache_saving_summary(true, _default_branch?, _branches), do: dgettext("dashboard_runners", "Any branch")

  def cache_saving_summary(false, default_branch?, branches) do
    labels = if default_branch?, do: [dgettext("dashboard_runners", "Default branch") | branches], else: branches

    cond do
      "*" in branches ->
        dgettext("dashboard_runners", "Any branch")

      labels == [] ->
        dgettext("dashboard_runners", "No branches")

      true ->
        case Enum.split(labels, 2) do
          {shown, []} ->
            Enum.join(shown, ", ")

          {shown, rest} ->
            dngettext(
              "dashboard_runners",
              "%{branches} + %{count} more",
              "%{branches} + %{count} more",
              length(rest),
              branches: Enum.join(shown, ", ")
            )
        end
    end
  end

  @doc """
  Platform a profile runs on. Reads off the stored `platform` field.
  """
  def platform_label(%Profile{platform: :linux}), do: dgettext("dashboard_runners", "Linux")
  def platform_label(%Profile{platform: :macos}), do: dgettext("dashboard_runners", "macOS")

  @doc """
  Noora badge color for a profile's platform, matching the Platform
  column on the Jobs table: `attention` (warm) for Linux,
  `information` (cool) for macOS.
  """
  def platform_badge_color(%Profile{platform: :linux}), do: "attention"
  def platform_badge_color(%Profile{platform: :macos}), do: "information"

  @doc """
  Platforms selectable in the create form. Order matters — the first
  is what the form lands on by default.
  """
  def platforms,
    do: [
      %{value: "linux", label: dgettext("dashboard_runners", "Linux")},
      %{value: "macos", label: dgettext("dashboard_runners", "macOS")}
    ]

  @doc """
  Operating system label for the macOS form field, which is static: the
  macOS image builds on a floating Tahoe base and the Mac minis hosting it
  adopt on the family rather than a point release, both by design —
  Scaleway retires point releases without notice, and pinning one stranded
  the staging fleet in Aug 2026. So the label names the family only.
  Linux profiles pick an Ubuntu release instead (`os_version_label/1`).
  """
  def os_label_for_form("macos"), do: dgettext("dashboard_runners", "Tahoe")
  def os_label_for_form(_), do: ""

  @doc """
  OS label for a persisted `%Profile{}`, for the table column: the Linux
  profile's Ubuntu release, or macOS's family.
  """
  def os_label(%Profile{platform: :linux, os_version: os_version}), do: os_version_label(os_version)
  def os_label(%Profile{platform: :macos}), do: os_label_for_form("macos")

  @doc """
  Display label for a Linux `os_version` (`ubuntu-24.04` → `Ubuntu 24.04`),
  from the catalog. A version the catalog no longer lists shows its
  raw value; a profile without one runs on the catalog default.
  """
  def os_version_label(nil) do
    case Catalog.default_os_version() do
      nil -> ""
      default -> default.label
    end
  end

  def os_version_label(os_version) when is_binary(os_version) do
    case Catalog.find_os_version(os_version) do
      nil -> os_version
      entry -> entry.label
    end
  end

  @doc """
  Label for the platform dropdown trigger, resolved from the selected
  value. Falls back to a placeholder when nothing matches.
  """
  def platform_label_for_value(value) do
    case Enum.find(platforms(), &(&1.value == value)) do
      %{label: label} -> label
      _ -> dgettext("dashboard_runners", "Select platform")
    end
  end

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

  @doc """
  The shape catalog the form should render in the Resources dropdown,
  picked from the live socket assigns based on the current platform.
  """
  def shape_catalog_for(catalog, _macos_catalog, "linux"), do: catalog
  def shape_catalog_for(_catalog, macos_catalog, "macos"), do: macos_catalog
  def shape_catalog_for(catalog, _, _), do: catalog

  @doc """
  Label for the Xcode-version dropdown trigger, resolved from the
  selected `xcode_version` string. Falls back to a placeholder.
  """
  def xcode_version_label_for_value(nil), do: dgettext("dashboard_runners", "Select Xcode version")

  def xcode_version_label_for_value(""), do: dgettext("dashboard_runners", "Select Xcode version")

  def xcode_version_label_for_value(version) when is_binary(version),
    do: dgettext("dashboard_runners", "Xcode %{version}", version: version)

  defp humanize_changeset_errors(%Ecto.Changeset{errors: errors}) do
    Enum.map_join(errors, "; ", fn {field, {msg, opts}} ->
      msg = Enum.reduce(opts, msg, fn {key, value}, acc -> String.replace(acc, "%{#{key}}", to_string(value)) end)
      "#{field}: #{msg}"
    end)
  end
end
