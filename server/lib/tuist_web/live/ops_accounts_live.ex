defmodule TuistWeb.OpsAccountsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import Ecto.Query, only: [from: 2]

  alias Phoenix.LiveView.JS
  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Billing
  alias Tuist.Billing.Subscription
  alias Tuist.Repo
  alias TuistWeb.Utilities.Query

  @page_size 30

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :head_title, "Accounts · Tuist Ops")}
  end

  @impl true
  def handle_params(_params, uri, socket) do
    query_params = Query.query_params(uri)
    search = query_params["search"] || ""
    page = parse_page(query_params["page"])

    filters =
      case search do
        "" -> []
        term -> [%{field: :search, op: :==, value: term}]
      end

    {accounts, meta} =
      Accounts.list_accounts(%{
        page: page,
        page_size: @page_size,
        filters: filters
      })

    accounts =
      Repo.preload(accounts, [
        :organization,
        :user,
        subscriptions:
          from(s in Subscription,
            where: s.status in ["active", "trialing"],
            order_by: [desc: s.inserted_at]
          )
      ])

    {:noreply,
     socket
     |> assign(:query_params, query_params)
     |> assign(:search, search)
     |> assign(:current_page, page)
     |> assign(:accounts, accounts)
     |> assign(:meta, meta)}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    params =
      socket.assigns.query_params
      |> Map.put("search", search)
      |> Map.delete("page")

    {:noreply, push_patch(socket, to: ~p"/ops/accounts?#{params}")}
  end

  @impl true
  def handle_event("manage", %{"id" => id}, socket) do
    case Accounts.get_account_by_id(String.to_integer(id)) do
      {:ok, account} ->
        account = Accounts.create_customer_when_absent(account)
        session = Billing.create_session(account.customer_id)
        {:noreply, redirect(socket, external: session.url)}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Account not found.")}
    end
  end

  @impl true
  def handle_event("submit_enterprise_upgrade", params, socket) do
    case Accounts.get_account_by_id(String.to_integer(params["account_id"])) do
      {:ok, account} ->
        {:ok, _sub} = Billing.upgrade_to_enterprise(account, parse_upgrade_params(params))

        {:noreply,
         socket
         |> put_flash(
           :info,
           "#{account.name} upgraded to Enterprise. Stripe will send an invoice for the first period."
         )
         |> push_event("phx:close-modal", %{id: "enterprise-modal-#{account.id}"})
         |> push_patch(to: ~p"/ops/accounts?#{socket.assigns.query_params}")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Account not found.")}
    end
  end

  @impl true
  def handle_event("cancel_plan", %{"id" => id}, socket) do
    with {:ok, account} <- Accounts.get_account_by_id(String.to_integer(id)),
         %_{} = subscription <- Billing.get_current_active_subscription(account),
         {:ok, _} <- Billing.cancel_subscription_at_period_end(subscription) do
      {:noreply,
       socket
       |> put_flash(:info, "#{account.name} plan set to cancel at the end of the current period.")
       |> push_patch(to: ~p"/ops/accounts?#{socket.assigns.query_params}")}
    else
      nil -> {:noreply, put_flash(socket, :error, "No active subscription to cancel.")}
      {:error, :not_found} -> {:noreply, put_flash(socket, :error, "Account not found.")}
      {:error, reason} -> {:noreply, put_flash(socket, :error, "Cancel failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("close-enterprise-modal-" <> _account_id, _params, socket) do
    # The modal closes itself via the Zag.js hook on escape / backdrop click /
    # the Cancel button. We acknowledge the event so LiveView doesn't warn.
    {:noreply, socket}
  end

  defp parse_upgrade_params(params) do
    %{
      name: params["name"],
      billing_email: params["billing_email"],
      cadence: params["cadence"] || "monthly",
      address: %{
        line1: params["address_line1"],
        line2: blank_to_nil(params["address_line2"]),
        city: params["address_city"],
        state: blank_to_nil(params["address_state"]),
        postal_code: params["address_postal_code"],
        country: String.upcase(params["address_country"] || "")
      }
    }
  end

  defp parse_page(nil), do: 1

  defp parse_page(value) do
    case Integer.parse(to_string(value)) do
      {page, _} when page > 0 -> page
      _ -> 1
    end
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  def account_type(%Account{organization_id: organization_id}) when not is_nil(organization_id), do: "Organization"
  def account_type(%Account{user_id: user_id}) when not is_nil(user_id), do: "User"
  def account_type(_), do: "Unknown"

  def current_plan(%Account{subscriptions: [%{plan: plan} | _]}), do: plan
  def current_plan(_), do: :air

  def plan_label(:air), do: "Air"
  def plan_label(:pro), do: "Pro"
  def plan_label(:enterprise), do: "Enterprise"
  def plan_label(:open_source), do: "Open Source"
  def plan_label(_), do: "Unknown"

  def plan_color(:air), do: "neutral"
  def plan_color(:pro), do: "primary"
  def plan_color(:enterprise), do: "success"
  def plan_color(:open_source), do: "information"
  def plan_color(_), do: "neutral"

  # ISO 3166-1 alpha-2 codes for the countries most likely to appear on
  # Enterprise invoices. Extend as needed. Sorted alphabetically by name.
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
