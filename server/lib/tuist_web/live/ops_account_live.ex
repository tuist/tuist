defmodule TuistWeb.OpsAccountLive do
  @moduledoc """
  Account detail page in /ops. The hub for everything an operator does
  on a single account: plan / billing actions (Stripe, Enterprise
  upgrade, cancel) and Kura mesh management.
  """
  use TuistWeb, :live_view
  use Noora

  import Ecto.Query, only: [from: 2]
  import TuistWeb.OpsAccountHelpers

  alias Phoenix.LiveView.JS
  alias Tuist.Accounts
  alias Tuist.Accounts.AccountCacheEndpoint
  alias Tuist.Billing
  alias Tuist.Billing.Subscription
  alias Tuist.Kura
  alias Tuist.Kura.Clusters
  alias Tuist.Repo

  require Logger

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Accounts.get_account_by_id(parse_id(id)) do
      {:ok, account} ->
        account = preload_billing(account)

        {:ok,
         socket
         |> assign(:head_title, "#{account.name} · Tuist Ops")
         |> assign(:account, account)
         |> assign(:upgrade_target_account, nil)
         |> assign(:upgrade_target_customer, nil)
         |> load_kura_state()}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Account not found.")
         |> push_navigate(to: ~p"/ops/accounts")}
    end
  end

  defp preload_billing(account) do
    Repo.preload(account, [
      :organization,
      :user,
      subscriptions:
        from(s in Subscription,
          where: s.status in ["active", "trialing"],
          order_by: [desc: s.inserted_at]
        )
    ])
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

  ## Plan & billing event handlers (moved from OpsAccountsLive)

  @impl true
  def handle_event("initiate_enterprise_upgrade", _params, socket) do
    account = Accounts.create_customer_when_absent(socket.assigns.account)
    customer = fetch_stripe_customer(account.customer_id)

    if customer_has_billing_details?(customer) do
      # Customer already has name/email/address on Stripe — upgrade in
      # one click without prompting ops to re-enter anything.
      {:ok, _sub} = Billing.upgrade_to_enterprise(account, %{cadence: "monthly"})

      {:noreply,
       socket
       |> assign(:account, preload_billing(account))
       |> put_flash(
         :info,
         "#{account.name} upgraded to Enterprise. Stripe will send an invoice for the first period."
       )}
    else
      # Missing billing details — open the modal pre-filled with whatever
      # the Stripe customer already has.
      {:noreply,
       socket
       |> assign(:upgrade_target_account, account)
       |> assign(:upgrade_target_customer, customer)
       |> push_event("open-modal", %{id: "enterprise-modal"})}
    end
  end

  @impl true
  def handle_event("submit_enterprise_upgrade", params, socket) do
    {:ok, _sub} = Billing.upgrade_to_enterprise(socket.assigns.account, parse_upgrade_params(params))

    account = preload_billing(socket.assigns.account)

    {:noreply,
     socket
     |> assign(:account, account)
     |> assign(:upgrade_target_account, nil)
     |> assign(:upgrade_target_customer, nil)
     |> put_flash(
       :info,
       "#{account.name} upgraded to Enterprise. Stripe will send an invoice for the first period."
     )
     |> push_event("close-modal", %{id: "enterprise-modal"})}
  end

  @impl true
  def handle_event("cancel_plan", _params, socket) do
    account = socket.assigns.account

    case Billing.get_current_active_subscription(account) do
      nil ->
        {:noreply, put_flash(socket, :error, "No active subscription to cancel.")}

      %_{} = subscription ->
        case Billing.cancel_subscription_at_period_end(subscription) do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(:account, preload_billing(account))
             |> put_flash(:info, "#{account.name} plan set to cancel at the end of the current period.")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Cancel failed: #{inspect(reason)}")}
        end
    end
  end

  @impl true
  def handle_event("close_enterprise_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:upgrade_target_account, nil)
     |> assign(:upgrade_target_customer, nil)
     |> push_event("close-modal", %{id: "enterprise-modal"})}
  end

  ## View helpers

  def cluster_kubeconfig_status(%Clusters{id: id}) do
    case Tuist.Environment.kura_kubeconfig(id) do
      nil -> :missing
      _ -> :configured
    end
  end

  def deployment_status_label(:pending), do: "Pending"
  def deployment_status_label(:running), do: "Running"
  def deployment_status_label(:succeeded), do: "Succeeded"
  def deployment_status_label(:failed), do: "Failed"
  def deployment_status_label(:cancelled), do: "Cancelled"

  def deployment_status_color(:pending), do: "neutral"
  def deployment_status_color(:running), do: "information"
  def deployment_status_color(:succeeded), do: "success"
  def deployment_status_color(:failed), do: "destructive"
  def deployment_status_color(:cancelled), do: "warning"

  ## Stripe-customer prefill helpers (moved from OpsAccountsLive)

  defp fetch_stripe_customer(nil), do: %{}

  defp fetch_stripe_customer(customer_id) do
    case Stripe.Customer.retrieve(customer_id) do
      {:ok, customer} -> customer
      _ -> %{}
    end
  end

  defp customer_has_billing_details?(%{address: %{} = address} = customer) do
    Enum.all?(
      [
        Map.get(customer, :name),
        Map.get(customer, :email),
        address.line1,
        address.city,
        address.postal_code,
        address.country
      ],
      &(is_binary(&1) and &1 != "")
    )
  end

  defp customer_has_billing_details?(_), do: false

  def prefill(customer, field, fallback \\ "")
  def prefill(nil, _field, fallback), do: fallback
  def prefill(%{} = customer, field, fallback), do: Map.get(customer, field) || fallback

  def prefill_address(nil, _field), do: ""

  def prefill_address(%{address: %{} = address}, field) do
    Map.get(address, field) || ""
  end

  def prefill_address(_, _), do: ""

  defp parse_upgrade_params(params) do
    %{
      name: params["name"],
      billing_email: params["billing_email"],
      cadence: params["cadence"] || "monthly",
      address: %{
        line1: params["address_line1"],
        line2: params["address_line2"],
        city: params["address_city"],
        state: params["address_state"],
        postal_code: params["address_postal_code"],
        country: String.upcase(params["address_country"] || "")
      }
    }
  end

  # ISO 3166-1 alpha-2 codes for the countries most likely to appear on
  # Enterprise invoices. Sorted alphabetically by name.
  @countries [
    {"AR", "Argentina"},
    {"AU", "Australia"},
    {"AT", "Austria"},
    {"BE", "Belgium"},
    {"BR", "Brazil"},
    {"BG", "Bulgaria"},
    {"CA", "Canada"},
    {"CL", "Chile"},
    {"CN", "China"},
    {"CO", "Colombia"},
    {"HR", "Croatia"},
    {"CY", "Cyprus"},
    {"CZ", "Czechia"},
    {"DK", "Denmark"},
    {"EE", "Estonia"},
    {"FI", "Finland"},
    {"FR", "France"},
    {"DE", "Germany"},
    {"GR", "Greece"},
    {"HK", "Hong Kong"},
    {"HU", "Hungary"},
    {"IS", "Iceland"},
    {"IN", "India"},
    {"ID", "Indonesia"},
    {"IE", "Ireland"},
    {"IL", "Israel"},
    {"IT", "Italy"},
    {"JP", "Japan"},
    {"LV", "Latvia"},
    {"LT", "Lithuania"},
    {"LU", "Luxembourg"},
    {"MY", "Malaysia"},
    {"MT", "Malta"},
    {"MX", "Mexico"},
    {"NL", "Netherlands"},
    {"NZ", "New Zealand"},
    {"NO", "Norway"},
    {"PH", "Philippines"},
    {"PL", "Poland"},
    {"PT", "Portugal"},
    {"RO", "Romania"},
    {"SG", "Singapore"},
    {"SK", "Slovakia"},
    {"SI", "Slovenia"},
    {"ZA", "South Africa"},
    {"KR", "South Korea"},
    {"ES", "Spain"},
    {"SE", "Sweden"},
    {"CH", "Switzerland"},
    {"TW", "Taiwan"},
    {"TH", "Thailand"},
    {"TR", "Turkey"},
    {"UA", "Ukraine"},
    {"AE", "United Arab Emirates"},
    {"GB", "United Kingdom"},
    {"US", "United States"},
    {"UY", "Uruguay"},
    {"VN", "Vietnam"}
  ]

  def countries, do: @countries
end
