defmodule TuistWeb.RunnerProfileLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Authorization
  alias Tuist.FeatureFlags
  alias Tuist.Runners.Catalog
  alias Tuist.Runners.Profile
  alias Tuist.Runners.Profiles
  alias TuistWeb.Errors.NotFoundError

  @impl true
  def mount(%{"name" => name}, _session, %{assigns: %{selected_account: account, current_user: current_user}} = socket) do
    if Authorization.authorize(:projects_read, current_user, account) != :ok or
         not FeatureFlags.runners_enabled?(account) do
      raise NotFoundError,
            dgettext("dashboard_runners", "The page you are looking for doesn't exist or has been moved.")
    end

    catalog = Catalog.list()

    {mode, profile, attrs} = load_profile(account, name, catalog)

    {:ok,
     socket
     |> assign(:head_title, head_title(account, name, mode))
     |> assign(:mode, mode)
     |> assign(:profile, profile)
     |> assign(:catalog, catalog)
     |> assign(:catalog_options, catalog_options(catalog))
     |> assign_changeset(attrs)}
  end

  @impl true
  def handle_event("validate", %{"profile" => params}, socket) do
    {:noreply, assign_changeset(socket, params)}
  end

  def handle_event("save", %{"profile" => params}, %{assigns: %{mode: :new, selected_account: account}} = socket) do
    case Profiles.create(account, with_parsed_shape(params)) do
      {:ok, profile} ->
        {:noreply,
         socket
         |> put_flash(:info, dgettext("dashboard_runners", "Profile %{name} created.", name: profile.name))
         |> push_navigate(to: ~p"/#{account.name}/runners/profiles")}

      {:error, :max_profiles_reached} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("dashboard_runners", "Profile limit reached (%{max}).", max: Profiles.max_per_account())
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, %{changeset | action: :insert})}
    end
  end

  def handle_event(
        "save",
        %{"profile" => params},
        %{assigns: %{mode: :edit, profile: profile, selected_account: account}} = socket
      ) do
    case Profiles.update(profile, with_parsed_shape(params)) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> put_flash(:info, dgettext("dashboard_runners", "Profile %{name} updated.", name: updated.name))
         |> push_navigate(to: ~p"/#{account.name}/runners/profiles")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, %{changeset | action: :update})}
    end
  end

  defp load_profile(_account, "new", _catalog) do
    default = catalog_default_or_first()

    attrs = %{
      "name" => "",
      "vcpus" => default && default.vcpus,
      "memory_gb" => default && default.memory_gb
    }

    {:new, %Profile{}, attrs}
  end

  defp load_profile(account, name, _catalog) do
    case Profiles.get_by_name(account, name) do
      nil ->
        raise NotFoundError,
              dgettext("dashboard_runners", "The page you are looking for doesn't exist or has been moved.")

      %Profile{} = profile ->
        {:edit, profile,
         %{
           "name" => profile.name,
           "vcpus" => profile.vcpus,
           "memory_gb" => profile.memory_gb
         }}
    end
  end

  defp catalog_default_or_first do
    case Catalog.default() do
      nil -> List.first(Catalog.list())
      shape -> shape
    end
  end

  defp catalog_options(catalog) do
    Enum.map(catalog, fn shape ->
      %{
        value: shape_value(shape),
        label: shape_label(shape),
        vcpus: shape.vcpus,
        memory_gb: shape.memory_gb,
        default?: shape.default?
      }
    end)
  end

  defp shape_value(%{vcpus: vcpus, memory_gb: memory_gb}), do: "#{vcpus}vcpu-#{memory_gb}gb"

  defp shape_label(%{vcpus: vcpus, memory_gb: memory_gb}), do: "#{vcpus} vCPU, #{memory_gb} GB RAM"

  defp assign_changeset(socket, params)

  defp assign_changeset(%{assigns: %{mode: :new, catalog: catalog}} = socket, params) do
    {vcpus, memory_gb} = parse_shape(params)

    attrs =
      params
      |> Map.put_new("vcpus", vcpus)
      |> Map.put_new("memory_gb", memory_gb)

    changeset = Profile.changeset(%Profile{}, attrs, catalog)
    assign(socket, :changeset, changeset)
  end

  defp assign_changeset(%{assigns: %{mode: :edit, profile: profile, catalog: catalog}} = socket, params) do
    {vcpus, memory_gb} = parse_shape(params)

    attrs =
      params
      |> Map.put("name", profile.name)
      |> Map.put_new("vcpus", vcpus)
      |> Map.put_new("memory_gb", memory_gb)

    changeset = Profile.changeset(profile, attrs, catalog)
    assign(socket, :changeset, changeset)
  end

  defp parse_shape(%{"shape" => shape}) when is_binary(shape) do
    case Regex.run(~r/^(\d+)vcpu-(\d+)gb$/, shape) do
      [_, vcpus, memory_gb] -> {String.to_integer(vcpus), String.to_integer(memory_gb)}
      _ -> {nil, nil}
    end
  end

  defp parse_shape(_), do: {nil, nil}

  defp with_parsed_shape(params) when is_map(params) do
    case parse_shape(params) do
      {nil, nil} ->
        params

      {vcpus, memory_gb} ->
        params
        |> Map.put("vcpus", vcpus)
        |> Map.put("memory_gb", memory_gb)
    end
  end

  defp head_title(account, "new", _mode) do
    "#{dgettext("dashboard_runners", "New profile")} · #{account.name} · Tuist"
  end

  defp head_title(account, name, _mode) do
    "#{name} · #{dgettext("dashboard_runners", "Profiles")} · #{account.name} · Tuist"
  end

  @doc """
  The `runs-on:` snippet to render in the preview card.
  Recomputed live as the form's name changes.
  """
  def dispatch_label_preview(name) when is_binary(name) and name != "", do: "tuist-" <> name
  def dispatch_label_preview(_), do: "tuist-<name>"

  @doc """
  Errors for a single changeset field, translated and ready for
  rendering. Returns `[]` when the changeset hasn't been actioned
  yet (so the page doesn't flash errors on first load).
  """
  def field_errors(%Ecto.Changeset{action: nil}, _field), do: []

  def field_errors(%Ecto.Changeset{} = changeset, field) do
    changeset.errors
    |> Keyword.get_values(field)
    |> Enum.map(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  @doc """
  True when the catalog `opt` matches the current `(vcpus, memory_gb)`
  on the changeset. Used to mark the selected `<option>` on first
  render and on every `validate` re-render.
  """
  def selected_shape?(%Ecto.Changeset{} = changeset, opt) do
    Ecto.Changeset.get_field(changeset, :vcpus) == opt.vcpus and
      Ecto.Changeset.get_field(changeset, :memory_gb) == opt.memory_gb
  end
end
