defmodule TuistWeb.OpsRegistryPackageLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Registry
  alias TuistWeb.Utilities.Query

  @page_size 30

  @impl true
  def mount(%{"scope" => scope, "name" => name}, _session, socket) do
    {:ok,
     socket
     |> assign(:head_title, "#{scope}/#{name} · Registry · Tuist Ops")
     |> assign(:scope, scope)
     |> assign(:name, name)
     |> assign_async(:package, fn ->
       case Registry.get_swift_package(scope, name) do
         {:ok, package} -> {:ok, %{package: package}}
         {:error, reason} -> {:error, reason}
       end
     end)}
  end

  @impl true
  def handle_params(_params, uri, socket) do
    query_params = Query.query_params(uri)

    {:noreply,
     socket
     |> assign(:query_params, query_params)
     |> assign(:search, query_params["search"] || "")
     |> assign(:page, parse_page(query_params["page"]))}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    params =
      socket.assigns.query_params
      |> Map.put("search", search)
      |> Map.delete("page")

    {:noreply,
     push_patch(socket,
       to: ~p"/ops/registry/#{socket.assigns.scope}/#{socket.assigns.name}?#{params}"
     )}
  end

  def handle_event("force_resync", %{"version" => version}, socket) do
    case socket.assigns.package do
      %{ok?: true, result: package} ->
        force_resync(package, version, socket)

      _ ->
        {:noreply, put_flash(socket, :error, "Package versions are still loading.")}
    end
  end

  defp force_resync(package, version, socket) do
    if Enum.any?(package.versions, &(&1.version == version)) do
      case Registry.force_resync_swift_package_version(package.repository_full_handle, version) do
        {:ok, %Oban.Job{conflict?: true}} ->
          {:noreply,
           put_flash(
             socket,
             :info,
             "A resync is already queued for #{package.repository_full_handle}@#{version}."
           )}

        {:ok, _job} ->
          {:noreply,
           put_flash(
             socket,
             :info,
             "Queued a resync for #{package.repository_full_handle}@#{version}."
           )}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Could not queue the resync. Please try again.")}
      end
    else
      {:noreply, put_flash(socket, :error, "That package version is no longer available.")}
    end
  end

  def filtered_versions(versions, search) do
    search = search |> String.trim() |> String.downcase()

    if search == "" do
      versions
    else
      Enum.filter(versions, fn version ->
        version.version
        |> String.downcase()
        |> String.contains?(search)
      end)
    end
  end

  def paginated_versions(versions, page) do
    Enum.slice(versions, (page - 1) * @page_size, @page_size)
  end

  def total_pages(versions) do
    versions
    |> length()
    |> Kernel./(@page_size)
    |> Float.ceil()
    |> trunc()
    |> max(1)
  end

  def current_page(page, total_pages), do: min(page, total_pages)

  def page_path(scope, name, query_params, page) do
    ~p"/ops/registry/#{scope}/#{name}?#{Map.put(query_params, "page", page)}"
  end

  def status_label(:available), do: "Available"
  def status_label(:skipped), do: "Skipped"

  def status_color(:available), do: "success"
  def status_color(:skipped), do: "warning"

  def detail_label(%{status: :available, detail: nil}), do: "Checksum unavailable"
  def detail_label(%{status: :skipped, detail: nil}), do: "Reason unavailable"

  def detail_label(%{status: :skipped, detail: detail}) do
    detail |> String.replace("_", " ") |> String.capitalize()
  end

  def detail_label(%{detail: detail}), do: detail

  defp parse_page(nil), do: 1

  defp parse_page(value) do
    case Integer.parse(to_string(value)) do
      {page, _} when page > 0 -> page
      _ -> 1
    end
  end
end
