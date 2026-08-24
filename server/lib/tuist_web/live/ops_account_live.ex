defmodule TuistWeb.OpsAccountLive do
  @moduledoc """
  Account detail page in /ops. The hub for everything an operator does
  on a single account: plan / billing actions (Stripe, Enterprise
  upgrade, cancel).
  """
  use TuistWeb, :live_view
  use Noora

  import Ecto.Query, only: [from: 2]
  import TuistWeb.OpsAccountHelpers

  alias Tuist.Accounts
  alias Tuist.Billing
  alias Tuist.Billing.Subscription
  alias Tuist.Kura
  alias Tuist.Repo
  alias Tuist.Runners.Concurrency
  alias Tuist.Runners.Prepaid
  alias Tuist.Runners.Trials

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Accounts.get_account_by_id(parse_id(id)) do
      {:ok, account} ->
        account = preload_billing(account)
        balance = Prepaid.balance(account)

        {:ok,
         socket
         |> assign(:head_title, "#{account.name} · Tuist Ops")
         |> assign(:account, account)
         |> assign(:runner_concurrency_form, runner_concurrency_form(account))
         |> assign(:prepaid_balance, balance)
         |> assign(:prepaid_minutes_value, held_minutes(balance))
         |> assign(:on_runner_trial, Trials.on_trial?(account))
         |> assign(:prepaid_quote, nil)
         |> assign(:has_subscription, not is_nil(Billing.get_current_active_subscription(account)))
         |> assign(:kura_minimum_claim, Kura.minimum_storage_claim())
         |> assign_kura_storage_claim(account)
         |> assign(:upgrade_target_account, nil)
         |> assign(:upgrade_target_customer, nil)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("dashboard", "Account not found."))
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
      {n, ""} -> n
      {_n, _rest} -> 0
      :error -> 0
    end
  end

  ## Plan & billing event handlers (moved from OpsAccountsLive)

  @impl true
  def handle_event("update_runner_concurrency_limits", %{"account" => params}, socket) do
    case Concurrency.update_limits(socket.assigns.account, params) do
      {:ok, account} ->
        account = preload_billing(account)

        {:noreply,
         socket
         |> assign(:account, account)
         |> assign(:runner_concurrency_form, runner_concurrency_form(account))
         |> put_flash(:info, dgettext("dashboard", "Runner concurrency limits updated."))}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:runner_concurrency_form, to_form(changeset, as: "account"))
         |> put_flash(:error, dgettext("dashboard", "Runner concurrency limits could not be updated."))}
    end
  end

  @impl true
  def handle_event("start_runner_trial", _params, socket) do
    case Trials.start(socket.assigns.account) do
      {:ok, account} ->
        {:noreply,
         socket
         |> assign(:account, preload_billing(account))
         |> assign(:on_runner_trial, true)
         |> put_flash(
           :info,
           dgettext(
             "dashboard",
             "%{account} is on a runner trial and will not be billed for runner usage until it is cancelled.",
             account: account.name
           )
         )}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, dgettext("dashboard", "Could not start the trial: %{reason}", reason: inspect(reason)))}
    end
  end

  @impl true
  def handle_event("cancel_runner_trial", _params, socket) do
    case Trials.cancel(socket.assigns.account) do
      {:ok, account} ->
        {:noreply,
         socket
         |> assign(:account, preload_billing(account))
         |> assign(:on_runner_trial, false)
         |> put_flash(
           :info,
           dgettext("dashboard", "%{account}'s runner trial is over. Runner usage is billable from now on.",
             account: account.name
           )
         )}

      {:error, reason} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("dashboard", "Could not cancel the trial: %{reason}", reason: inspect(reason))
         )}
    end
  end

  # Quoted live as ops types, so the money leaving the customer is on
  # screen before the charge is created rather than inferred from a
  # minute count.
  @impl true
  def handle_event("quote_prepaid_minutes", %{"minutes" => minutes}, socket) do
    {:noreply, assign(socket, :prepaid_quote, quote_minutes(minutes))}
  end

  @impl true
  def handle_event("set_prepaid_minutes", %{"minutes" => minutes}, socket) do
    case parse_minutes(minutes) do
      {:ok, minutes} ->
        account = Accounts.create_customer_when_absent(socket.assigns.account)

        case Prepaid.set_minutes(account, minutes) do
          {:ok, _result} ->
            quoted = Prepaid.quote_minutes(max(minutes, 1))
            refreshed = Prepaid.balance(account)

            {:noreply,
             socket
             |> assign(:account, preload_billing(account))
             |> assign(:prepaid_balance, refreshed)
             |> assign(:prepaid_minutes_value, held_minutes(refreshed))
             |> assign(:prepaid_quote, nil)
             |> put_flash(
               :info,
               dgettext(
                 "dashboard",
                 "%{account} now holds %{minutes} prepaid runner minutes. %{amount} was added to its next invoice.",
                 minutes: format_number(minutes),
                 amount: format_money(quoted.invoiced),
                 account: account.name
               )
             )}

          {:error, reason} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               dgettext("dashboard", "Could not set prepaid minutes: %{reason}", reason: inspect(reason))
             )}
        end

      :error ->
        {:noreply, put_flash(socket, :error, dgettext("dashboard", "Enter a whole number of minutes, or zero to clear."))}
    end
  end

  @impl true
  def handle_event("update_kura_storage_claim", %{"account" => params}, socket) do
    account = socket.assigns.account

    case Kura.update_storage_claim_override(account, params) do
      {:ok, result} ->
        {:noreply,
         socket
         |> assign_kura_storage_claim(account)
         |> put_flash(:info, kura_storage_claim_message(result))}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:kura_storage_claim_form, to_form(changeset, as: "account"))
         |> put_flash(:error, dgettext("dashboard", "Kura disk claim could not be updated."))}
    end
  end

  @impl true
  def handle_event("toggle_visibility", _params, socket) do
    account = socket.assigns.account
    visibility = if account.visibility == :public, do: :private, else: :public

    case Accounts.update_account_visibility(account, visibility) do
      {:ok, account} ->
        {:noreply,
         socket
         |> assign(:account, preload_billing(account))
         |> put_flash(
           :info,
           dgettext("dashboard", "%{account} is now %{visibility}.",
             account: account.name,
             visibility: account.visibility
           )
         )}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, dgettext("dashboard", "Account visibility could not be updated."))}
    end
  end

  @impl true
  def handle_event("initiate_enterprise_upgrade", _params, socket) do
    account = Accounts.create_customer_when_absent(socket.assigns.account)
    customer = fetch_stripe_customer(account.customer_id)

    if customer_has_billing_details?(customer) do
      # Customer already has name/email/address on Stripe: upgrade in
      # one click without prompting ops to re-enter anything.
      {:ok, _sub} = Billing.upgrade_to_enterprise(account, %{})

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

  defp quote_minutes(raw) do
    case parse_minutes(raw) do
      {:ok, minutes} when minutes > 0 -> Prepaid.quote_minutes(minutes)
      _ -> nil
    end
  end

  # The field opens on what the account holds, so an operator corrects a
  # figure rather than working out the difference from the table above.
  defp held_minutes(nil), do: 0

  defp held_minutes(%{grants: grants}) do
    grants |> Enum.map(&Map.get(&1, :available_minutes, 0)) |> Enum.sum()
  end

  defp parse_minutes(raw) when is_binary(raw) do
    case Integer.parse(String.trim(raw)) do
      {minutes, ""} when minutes >= 0 -> {:ok, minutes}
      _ -> :error
    end
  end

  defp parse_minutes(_raw), do: :error

  def prepaid_grant_kind_label("trial"), do: dgettext("dashboard", "Trial")
  def prepaid_grant_kind_label(_kind), do: dgettext("dashboard", "Prepaid")

  def prepaid_expiry_label(nil), do: dgettext("dashboard", "No expiry")
  def prepaid_expiry_label(%DateTime{} = expires_at), do: Timex.format!(expires_at, "{Mfull} {D}, {YYYY}")

  defp runner_concurrency_form(account) do
    account
    |> Concurrency.change_limits()
    |> to_form(as: "account")
  end

  # The rows, the form and the claim the rows resolve against move together: an
  # override write re-pins instances, so a table left on the old assign would
  # show claims that no longer exist.
  defp assign_kura_storage_claim(socket, account) do
    socket
    |> assign(:kura_servers, Kura.list_servers_for_account(account.id))
    |> assign(:kura_account_claim, Kura.effective_storage_claim(account))
    |> assign(:kura_plan_claim, Kura.plan_storage_claim(account))
    |> assign(:kura_storage_claim_form, kura_storage_claim_form(account))
  end

  defp kura_storage_claim_form(account) do
    account
    |> Kura.change_storage_claim_override()
    |> to_form(as: "account")
  end

  # Raising a claim and lowering one do different things to a running instance,
  # and only one of them costs a cache. Say which happened rather than reporting
  # a successful save: an operator raising a claim to rescue a capped account is
  # the one most likely to assume it was free.
  defp kura_storage_claim_message(%{claim_size: claim_size, raised: [], lowered: []}) do
    dgettext(
      "dashboard",
      "Kura disk claim set to %{claim}. No running instance changed; it applies the next time volumes are built.",
      claim: claim_size
    )
  end

  defp kura_storage_claim_message(%{claim_size: claim_size, raised: []} = result) do
    dngettext(
      "dashboard",
      "Kura disk claim lowered to %{claim}. %{count} running instance keeps its cache and evicts down to the new budget.",
      "Kura disk claim lowered to %{claim}. %{count} running instances keep their caches and evict down to the new budget.",
      length(result.lowered),
      claim: claim_size
    )
  end

  # "Up to", because an instance rebuilds only if its volumes are smaller than
  # the new claim, and an earlier decrease can have left them larger. The rebuild
  # rolls one replica at a time behind the standby, so it is a rollout rather
  # than an outage and the cache survives it where there is a standby to refill
  # from.
  defp kura_storage_claim_message(%{claim_size: claim_size} = result) do
    dngettext(
      "dashboard",
      "Kura disk claim raised to %{claim}. Up to %{count} running instance rebuilds its volumes, one replica at a time behind the standby that keeps serving.",
      "Kura disk claim raised to %{claim}. Up to %{count} running instances rebuild their volumes, one replica at a time behind the standby that keeps serving.",
      length(result.raised),
      claim: claim_size
    )
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
