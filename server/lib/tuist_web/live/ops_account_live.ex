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
  alias Tuist.Billing
  alias Tuist.Billing.Subscription
  alias Tuist.Kura
  alias Tuist.Kura.KuraServer
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Specs
  alias Tuist.Repo

  require Logger

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Accounts.get_account_by_id(parse_id(id)) do
      {:ok, account} ->
        account = preload_billing(account)
        if connected?(socket), do: Kura.subscribe_to_account(account.id)

        {:ok,
         socket
         |> assign(:head_title, "#{account.name} · Tuist Ops")
         |> assign(:account, account)
         |> assign(:upgrade_target_account, nil)
         |> assign(:upgrade_target_customer, nil)
         |> assign(:add_server_form, default_add_server_form())
         |> load_kura_state()}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Account not found.")
         |> push_navigate(to: ~p"/ops/accounts")}
    end
  end

  defp default_add_server_form do
    default_region = Regions.available() |> List.first()
    default_spec = :medium

    to_form(
      %{
        "region" => default_region && default_region.id,
        "spec" => Atom.to_string(default_spec),
        "volume_size_gi" => to_string(Specs.default_volume_gi(default_spec) || 200)
      },
      as: :server
    )
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
    latest = Kura.latest_versions(1) |> List.first()

    socket
    |> assign(:kura_servers, Kura.list_servers_for_account(account.id))
    |> assign(:kura_regions, Regions.available())
    |> assign(:kura_specs, Specs.all())
    |> assign(:latest_kura_version, latest)
  end

  ## Kura events

  @impl true
  def handle_event("open_add_server", _params, socket) do
    {:noreply, push_event(socket, "open-modal", %{id: "add-server-modal"})}
  end

  @impl true
  def handle_event("close_add_server", _params, socket) do
    {:noreply, push_event(socket, "close-modal", %{id: "add-server-modal"})}
  end

  @impl true
  def handle_event("submit_add_server", %{"server" => params}, socket) do
    case Kura.latest_versions(1) do
      [] ->
        {:noreply,
         put_flash(socket, :error, "No cached Kura version yet. Wait for the poll worker to see kura@*.")}

      [%{version: image_tag} | _] ->
        spec = parse_spec(params["spec"])

        attrs = %{
          account_id: socket.assigns.account.id,
          region: params["region"],
          spec: spec,
          volume_size_gi: parse_int(params["volume_size_gi"], Specs.default_volume_gi(spec) || 200),
          image_tag: image_tag
        }

        submit_add_server(socket, attrs)
    end
  end

  @impl true
  def handle_event("destroy_server", %{"id" => id}, socket) do
    case Kura.get_server(socket.assigns.account.id, id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Server not found.")}

      %KuraServer{} = server ->
        {:ok, _} = Kura.destroy_server(server)
        {:noreply, socket |> put_flash(:info, "Destroying Kura server…") |> load_kura_state()}
    end
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

  @impl true
  def handle_info({:kura_server, _event, _server}, socket) do
    {:noreply, load_kura_state(socket)}
  end

  ## Add-server helpers

  defp parse_spec("small"), do: :small
  defp parse_spec("large"), do: :large
  defp parse_spec(_), do: :medium

  defp submit_add_server(socket, attrs) do
    case Kura.create_server(attrs) do
      {:ok, server} ->
        {:noreply,
         socket
         |> put_flash(:info, "Provisioning Kura server in #{server.region}…")
         |> assign(:add_server_form, default_add_server_form())
         |> push_event("close-modal", %{id: "add-server-modal"})
         |> load_kura_state()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to provision: #{format_errors(changeset)}")
         |> push_event("close-modal", %{id: "add-server-modal"})}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to provision: #{inspect(reason)}")
         |> push_event("close-modal", %{id: "add-server-modal"})}
    end
  end

  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} when n > 0 -> n
      _ -> default
    end
  end

  defp parse_int(_, default), do: default

  defp format_errors(%Ecto.Changeset{errors: errors}) do
    errors
    |> Enum.map_join(", ", fn {field, {msg, _}} -> "#{field} #{msg}" end)
  end

  ## View helpers

  def region_kubeconfig_status(%Regions{provisioner_config: %{cluster_id: cluster_id}}) do
    case Tuist.Environment.kura_kubeconfig(cluster_id) do
      nil -> :missing
      "" -> :missing
      _ -> :configured
    end
  end

  def region_kubeconfig_status(_), do: :configured

  def server_status_label(:provisioning), do: "Provisioning"
  def server_status_label(:active), do: "Active"
  def server_status_label(:failed), do: "Failed"
  def server_status_label(:destroying), do: "Destroying"
  def server_status_label(:destroyed), do: "Destroyed"

  def server_status_color(:provisioning), do: "information"
  def server_status_color(:active), do: "success"
  def server_status_color(:failed), do: "destructive"
  def server_status_color(:destroying), do: "warning"
  def server_status_color(:destroyed), do: "neutral"

  def spec_label(spec) when is_atom(spec) do
    case Specs.get(spec) do
      %Specs{label: label} -> label
      _ -> Atom.to_string(spec)
    end
  end

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
