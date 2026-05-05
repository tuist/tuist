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

  alias Tuist.Accounts
  alias Tuist.Billing
  alias Tuist.Billing.Subscription
  alias Tuist.Kura
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Server
  alias Tuist.Kura.Specs
  alias Tuist.Repo

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
         |> put_flash(:error, dgettext("dashboard", "Account not found."))
         |> push_navigate(to: ~p"/ops/accounts")}
    end
  end

  defp default_add_server_form do
    default_region = List.first(Regions.available())
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
    latest = List.first(Kura.latest_versions(1))

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
         put_flash(
           socket,
           :error,
           dgettext("dashboard", "Could not resolve a Kura release from GitHub right now. Try again shortly.")
         )}

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
        {:noreply, put_flash(socket, :error, dgettext("dashboard", "Server not found."))}

      %Server{} = server ->
        {:ok, _} = Kura.destroy_server(server)
        {:noreply, socket |> put_flash(:info, dgettext("dashboard", "Destroying Kura server...")) |> load_kura_state()}
    end
  end

  ## Plan & billing event handlers (moved from OpsAccountsLive)

  @impl true
  def handle_event("initiate_enterprise_upgrade", _params, socket) do
    account = Accounts.create_customer_when_absent(socket.assigns.account)
    customer = fetch_stripe_customer(account.customer_id)

    if customer_has_billing_details?(customer) do
      # Customer already has name/email/address on Stripe: upgrade in
      # one click without prompting ops to re-enter anything.
      {:ok, _sub} = Billing.upgrade_to_enterprise(account, %{cadence: "monthly"})

      {:noreply,
       socket
       |> assign(:account, preload_billing(account))
       |> put_flash(
         :info,
         dgettext("dashboard", "%{account} upgraded to Enterprise. Stripe will send an invoice for the first period.",
           account: account.name
         )
       )}
    else
      # Missing billing details: open the modal pre-filled with whatever
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
       dgettext("dashboard", "%{account} upgraded to Enterprise. Stripe will send an invoice for the first period.",
         account: account.name
       )
     )
     |> push_event("close-modal", %{id: "enterprise-modal"})}
  end

  @impl true
  def handle_event("cancel_plan", _params, socket) do
    account = socket.assigns.account

    case Billing.get_current_active_subscription(account) do
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("dashboard", "No active subscription to cancel."))}

      %_{} = subscription ->
        case Billing.cancel_subscription_at_period_end(subscription) do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(:account, preload_billing(account))
             |> put_flash(
               :info,
               dgettext("dashboard", "%{account} plan set to cancel at the end of the current period.",
                 account: account.name
               )
             )}

          {:error, reason} ->
            {:noreply,
             put_flash(socket, :error, dgettext("dashboard", "Cancel failed: %{reason}", reason: inspect(reason)))}
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
         |> put_flash(
           :info,
           dgettext("dashboard", "Creating Kura server in %{region}...", region: server.region)
         )
         |> assign(:add_server_form, default_add_server_form())
         |> push_event("close-modal", %{id: "add-server-modal"})
         |> load_kura_state()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           dgettext("dashboard", "Failed to create Kura server: %{reason}", reason: format_errors(changeset))
         )
         |> push_event("close-modal", %{id: "add-server-modal"})}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           dgettext("dashboard", "Failed to create Kura server: %{reason}", reason: inspect(reason))
         )
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
    Enum.map_join(errors, ", ", fn {field, {msg, _}} -> "#{field} #{msg}" end)
  end

  ## View helpers

  def server_status_label(:provisioning), do: dgettext("dashboard", "Creating")
  def server_status_label(:active), do: dgettext("dashboard", "Active")
  def server_status_label(:failed), do: dgettext("dashboard", "Failed")
  def server_status_label(:destroying), do: dgettext("dashboard", "Destroying")
  def server_status_label(:destroyed), do: dgettext("dashboard", "Destroyed")

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
  @country_codes ~w(AR AU AT BE BR BG CA CL CN CO HR CY CZ DK EE FI FR DE GR HK HU IS IN ID IE IL IT JP LV LT LU MY MT MX NL NZ NO PH PL PT RO SG SK SI ZA KR ES SE CH TW TH TR UA AE GB US UY VN)

  def countries, do: Enum.map(@country_codes, &{&1, country_name(&1)})

  defp country_name("AR"), do: dgettext("dashboard", "Argentina")
  defp country_name("AU"), do: dgettext("dashboard", "Australia")
  defp country_name("AT"), do: dgettext("dashboard", "Austria")
  defp country_name("BE"), do: dgettext("dashboard", "Belgium")
  defp country_name("BR"), do: dgettext("dashboard", "Brazil")
  defp country_name("BG"), do: dgettext("dashboard", "Bulgaria")
  defp country_name("CA"), do: dgettext("dashboard", "Canada")
  defp country_name("CL"), do: dgettext("dashboard", "Chile")
  defp country_name("CN"), do: dgettext("dashboard", "China")
  defp country_name("CO"), do: dgettext("dashboard", "Colombia")
  defp country_name("HR"), do: dgettext("dashboard", "Croatia")
  defp country_name("CY"), do: dgettext("dashboard", "Cyprus")
  defp country_name("CZ"), do: dgettext("dashboard", "Czechia")
  defp country_name("DK"), do: dgettext("dashboard", "Denmark")
  defp country_name("EE"), do: dgettext("dashboard", "Estonia")
  defp country_name("FI"), do: dgettext("dashboard", "Finland")
  defp country_name("FR"), do: dgettext("dashboard", "France")
  defp country_name("DE"), do: dgettext("dashboard", "Germany")
  defp country_name("GR"), do: dgettext("dashboard", "Greece")
  defp country_name("HK"), do: dgettext("dashboard", "Hong Kong")
  defp country_name("HU"), do: dgettext("dashboard", "Hungary")
  defp country_name("IS"), do: dgettext("dashboard", "Iceland")
  defp country_name("IN"), do: dgettext("dashboard", "India")
  defp country_name("ID"), do: dgettext("dashboard", "Indonesia")
  defp country_name("IE"), do: dgettext("dashboard", "Ireland")
  defp country_name("IL"), do: dgettext("dashboard", "Israel")
  defp country_name("IT"), do: dgettext("dashboard", "Italy")
  defp country_name("JP"), do: dgettext("dashboard", "Japan")
  defp country_name("LV"), do: dgettext("dashboard", "Latvia")
  defp country_name("LT"), do: dgettext("dashboard", "Lithuania")
  defp country_name("LU"), do: dgettext("dashboard", "Luxembourg")
  defp country_name("MY"), do: dgettext("dashboard", "Malaysia")
  defp country_name("MT"), do: dgettext("dashboard", "Malta")
  defp country_name("MX"), do: dgettext("dashboard", "Mexico")
  defp country_name("NL"), do: dgettext("dashboard", "Netherlands")
  defp country_name("NZ"), do: dgettext("dashboard", "New Zealand")
  defp country_name("NO"), do: dgettext("dashboard", "Norway")
  defp country_name("PH"), do: dgettext("dashboard", "Philippines")
  defp country_name("PL"), do: dgettext("dashboard", "Poland")
  defp country_name("PT"), do: dgettext("dashboard", "Portugal")
  defp country_name("RO"), do: dgettext("dashboard", "Romania")
  defp country_name("SG"), do: dgettext("dashboard", "Singapore")
  defp country_name("SK"), do: dgettext("dashboard", "Slovakia")
  defp country_name("SI"), do: dgettext("dashboard", "Slovenia")
  defp country_name("ZA"), do: dgettext("dashboard", "South Africa")
  defp country_name("KR"), do: dgettext("dashboard", "South Korea")
  defp country_name("ES"), do: dgettext("dashboard", "Spain")
  defp country_name("SE"), do: dgettext("dashboard", "Sweden")
  defp country_name("CH"), do: dgettext("dashboard", "Switzerland")
  defp country_name("TW"), do: dgettext("dashboard", "Taiwan")
  defp country_name("TH"), do: dgettext("dashboard", "Thailand")
  defp country_name("TR"), do: dgettext("dashboard", "Turkey")
  defp country_name("UA"), do: dgettext("dashboard", "Ukraine")
  defp country_name("AE"), do: dgettext("dashboard", "United Arab Emirates")
  defp country_name("GB"), do: dgettext("dashboard", "United Kingdom")
  defp country_name("US"), do: dgettext("dashboard", "United States")
  defp country_name("UY"), do: dgettext("dashboard", "Uruguay")
  defp country_name("VN"), do: dgettext("dashboard", "Vietnam")
end
