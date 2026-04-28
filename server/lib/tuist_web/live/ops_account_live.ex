defmodule TuistWeb.OpsAccountLive do
  @moduledoc """
  Account detail page in /ops. The first iteration focuses on the Kura
  section — bound meshes, the `:kura` feature flag, and the
  add/remove/deploy controls. Broader account details can be added in
  follow-ups.
  """
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Accounts
  alias Tuist.Accounts.AccountCacheEndpoint
  alias Tuist.Kura
  alias Tuist.Kura.Clusters

  require Logger

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Accounts.get_account_by_id(parse_id(id)) do
      {:ok, account} ->
        {:ok,
         socket
         |> assign(:head_title, "#{account.name} · Tuist Ops")
         |> assign(:account, account)
         |> load_kura_state()}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Account not found.")
         |> push_navigate(to: ~p"/ops/accounts")}
    end
  end

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp load_kura_state(socket) do
    account = socket.assigns.account

    bound = Accounts.list_account_cache_endpoints(account, :kura)
    bound_cluster_ids = Enum.map(bound, &cluster_id_from_url/1) |> Enum.reject(&is_nil/1)

    socket
    |> assign(:kura_flag_enabled?, FunWithFlags.enabled?(:kura, for: account))
    |> assign(:kura_bound, bound)
    |> assign(:kura_bound_cluster_ids, bound_cluster_ids)
    |> assign(:kura_clusters, Clusters.all())
    |> assign(:kura_versions, Kura.latest_versions(20))
    |> assign(:kura_deployments, Kura.list_deployments_for_account(account.id, 20))
  end

  # Pull the cluster ID out of the stored URL by reversing the host
  # template `<account>-<cluster>.kura.tuist.dev`. Returns nil if the URL
  # doesn't match (e.g. it was inserted before this convention).
  def cluster_id_from_url_helper(%AccountCacheEndpoint{} = endpoint), do: cluster_id_from_url(endpoint)

  defp cluster_id_from_url(%AccountCacheEndpoint{url: url}) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) ->
        case String.split(host, ".kura.") do
          [prefix, _] ->
            case String.split(prefix, "-", parts: 2) do
              [_account, cluster_id] -> cluster_id
              _ -> nil
            end

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  @impl true
  def handle_event("toggle_kura_flag", _params, socket) do
    account = socket.assigns.account

    if socket.assigns.kura_flag_enabled? do
      {:ok, _} = FunWithFlags.disable(:kura, for_actor: account)
    else
      {:ok, _} = FunWithFlags.enable(:kura, for_actor: account)
    end

    {:noreply, load_kura_state(socket)}
  end

  @impl true
  def handle_event("bind_cluster", %{"cluster_id" => cluster_id}, socket) do
    account = socket.assigns.account

    case Clusters.get(cluster_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Unknown cluster #{cluster_id}.")}

      %Clusters{} = cluster ->
        url = Clusters.public_url(account.name, cluster)

        case Accounts.create_account_cache_endpoint(account, %{url: url, technology: :kura}) do
          {:ok, _endpoint} ->
            {:noreply,
             socket
             |> put_flash(:info, "Bound #{cluster_id} → #{url}")
             |> load_kura_state()}

          {:error, changeset} ->
            {:noreply,
             put_flash(socket, :error, "Failed to bind: #{inspect(changeset.errors)}")}
        end
    end
  end

  @impl true
  def handle_event("unbind", %{"id" => id}, socket) do
    case Accounts.get_account_cache_endpoint(socket.assigns.account, id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Endpoint not found.")}

      endpoint ->
        {:ok, _} = Accounts.delete_account_cache_endpoint(endpoint)
        {:noreply, socket |> put_flash(:info, "Endpoint removed.") |> load_kura_state()}
    end
  end

  @impl true
  def handle_event("deploy", %{"cluster_id" => cluster_id, "image_tag" => image_tag}, socket) do
    account = socket.assigns.account
    user = socket.assigns.current_user

    case Kura.create_deployment(%{
           account_id: account.id,
           cluster_id: cluster_id,
           image_tag: image_tag,
           requested_by_user_id: user && user.id
         }) do
      {:ok, deployment} ->
        {:noreply,
         socket
         |> put_flash(:info, "Queued deployment of #{image_tag} to #{cluster_id}.")
         |> push_navigate(
           to: ~p"/ops/accounts/#{account.id}/kura/deployments/#{deployment.id}"
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, put_flash(socket, :error, "Invalid deployment: #{inspect(changeset.errors)}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to queue: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("poll_versions_now", _params, socket) do
    {:ok, _job} =
      %{}
      |> Tuist.Kura.Workers.PollVersionsWorker.new()
      |> Oban.insert()

    {:noreply, put_flash(socket, :info, "Version poll scheduled.")}
  end

  ## View helpers

  def cluster_kubeconfig_status(%Clusters{id: id}) do
    case Tuist.Environment.kura_kubeconfig(id) do
      nil -> :missing
      _ -> :configured
    end
  end

  def status_label(:pending), do: "Pending"
  def status_label(:running), do: "Running"
  def status_label(:succeeded), do: "Succeeded"
  def status_label(:failed), do: "Failed"
  def status_label(:cancelled), do: "Cancelled"

  def status_color(:pending), do: "neutral"
  def status_color(:running), do: "information"
  def status_color(:succeeded), do: "success"
  def status_color(:failed), do: "destructive"
  def status_color(:cancelled), do: "warning"
end
