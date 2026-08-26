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
  alias Tuist.Utilities.ByteFormatter

  # Enough to see a pattern without the card becoming the page.
  @kura_claim_history_limit 5
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
            refreshed = Prepaid.balance(account)

            {:noreply,
             socket
             |> assign(:account, preload_billing(account))
             |> assign(:prepaid_balance, refreshed)
             |> assign(:prepaid_minutes_value, held_minutes(refreshed))
             |> assign(:prepaid_quote, nil)
             |> put_flash(:info, set_minutes_message(account, minutes))}

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
  def handle_event("apply_kura_claim_proposal", _params, socket) do
    account = socket.assigns.account
    proposal = socket.assigns.kura_claim_proposal

    case proposal && Kura.apply_claim_proposal(proposal, socket.assigns.current_user.email) do
      {:ok, result} ->
        {:noreply,
         socket
         |> assign_kura_storage_claim(account)
         |> put_flash(:info, kura_storage_claim_message(result))}

      _stale_or_missing ->
        {:noreply,
         socket
         |> assign_kura_storage_claim(account)
         |> put_flash(
           :error,
           dgettext(
             "dashboard",
             "The proposal no longer applies; the next sizing sweep re-evaluates the account."
           )
         )}
    end
  end

  @impl true
  def handle_event("dismiss_kura_claim_proposal", _params, socket) do
    account = socket.assigns.account
    proposal = socket.assigns.kura_claim_proposal

    case proposal && Kura.dismiss_claim_proposal(proposal, socket.assigns.current_user.email) do
      {:ok, _proposal} ->
        {:noreply,
         socket
         |> assign_kura_storage_claim(account)
         |> put_flash(:info, dgettext("dashboard", "Sizing proposal dismissed."))}

      _stale_or_missing ->
        {:noreply, assign_kura_storage_claim(socket, account)}
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

  defp set_minutes_message(account, 0) do
    dgettext("dashboard", "%{account} no longer holds any prepaid runner minutes.", account: account.name)
  end

  defp set_minutes_message(account, minutes) do
    quoted = Prepaid.quote_minutes(minutes)

    dgettext(
      "dashboard",
      "%{account} now holds %{minutes} prepaid runner minutes. %{amount} was added to its next invoice.",
      minutes: format_number(minutes),
      amount: format_money(quoted.invoiced),
      account: account.name
    )
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

  # The rows and the claim they resolve against move together: an applied
  # proposal re-pins instances, so a table left on the old assign would show
  # claims that no longer exist.
  defp assign_kura_storage_claim(socket, account) do
    socket
    |> assign(:kura_servers, Kura.list_servers_for_account(account.id))
    |> assign(:kura_account_claim, Kura.effective_storage_claim(account))
    |> assign(:kura_sized_claim, Kura.sized_storage_claim(account))
    |> assign(:kura_claim_proposal, Kura.claim_proposal_for(account))
    |> assign(:kura_claim_history, Kura.claim_sizing_history(account, @kura_claim_history_limit))
    |> assign(:kura_claim_history_total, Kura.claim_sizing_decision_count(account))
    |> assign(:kura_disk_usage, Kura.latest_storage_snapshots(account))
  end

  # The proposal's evidence differs by direction: growth argues from how young
  # the shed content was against the plan's retention floor, shrinking from
  # how empty the ring stayed.
  # Written for an operator deciding whether to trust the proposal: what the
  # cache is doing, what it is supposed to do instead, and how much evidence
  # sits behind it. No policy vocabulary — the windows and thresholds are ours,
  # not something the reader should have to look up.
  defp kura_claim_proposal_evidence(%{direction: :grow, evidence: evidence}) do
    dgettext(
      "dashboard",
      "The cache in %{region} is discarding work a median of %{shed_age} after it was written, when it should keep everything for at least %{floor}.",
      shed_age: humanize_seconds(evidence["median_shed_age_seconds"]),
      region: evidence["region"],
      floor: humanize_seconds(evidence["retention_floor_seconds"])
    )
  end

  defp kura_claim_proposal_evidence(%{direction: :shrink, evidence: evidence}) do
    dgettext(
      "dashboard",
      "The cache in %{region} has not filled past %{peak}% of the disk it reserves, and has discarded nothing.",
      region: evidence["region"],
      peak: evidence["max_occupancy_percent"]
    )
  end

  # The second line: how much observation stands behind the first. Days are
  # what the measurements are grouped into, so an operator can see whether this
  # is one bad afternoon or a standing pattern.
  defp kura_claim_proposal_basis(%{direction: :grow, evidence: evidence}) do
    dngettext(
      "dashboard",
      "Seen on %{count} day of measurements (%{bytes} discarded, %{turnover}x the whole cache).",
      "Seen on %{count} consecutive days of measurements (%{bytes} discarded, %{turnover}x the whole cache).",
      evidence["window_days"],
      bytes: ByteFormatter.format_bytes(evidence["evicted_bytes"] || 0),
      turnover: evidence["ring_turnover"] || 0
    )
  end

  defp kura_claim_proposal_basis(%{direction: :shrink, evidence: evidence}) do
    dngettext(
      "dashboard",
      "Seen on %{count} day of measurements.",
      "Seen on %{count} consecutive days of measurements.",
      evidence["window_days"]
    )
  end

  defp humanize_seconds(nil), do: dgettext("dashboard", "unknown")

  defp humanize_seconds(seconds) when is_integer(seconds) do
    cond do
      seconds >= 86_400 -> dgettext("dashboard", "%{count} days", count: Float.round(seconds / 86_400, 1))
      seconds >= 3_600 -> dgettext("dashboard", "%{count} hours", count: Float.round(seconds / 3_600, 1))
      true -> dgettext("dashboard", "%{count} minutes", count: div(seconds, 60))
    end
  end

  defp kura_claim_history_change(%{current_claim_size: from, recommended_claim_size: to}), do: "#{from} → #{to}"

  def claim_history_outcome(%{status: :applied}), do: {dgettext("dashboard", "applied"), "success"}
  def claim_history_outcome(%{status: :dismissed}), do: {dgettext("dashboard", "dismissed"), "neutral"}
  def claim_history_outcome(%{status: :superseded}), do: {dgettext("dashboard", "superseded"), "neutral"}
  def claim_history_outcome(%{status: :open}), do: {dgettext("dashboard", "waiting"), "attention"}

  def claim_history_actor(%{status: :open}), do: dgettext("dashboard", "Not resolved yet")

  def claim_history_actor(%{resolved_by: by}) when by in ["automatic", "sweep", "stale_on_apply"],
    do: dgettext("dashboard", "Sizing")

  def claim_history_actor(%{resolved_by: by}) when is_binary(by), do: by
  def claim_history_actor(_decision), do: dgettext("dashboard", "Unknown")

  # Compact enough for a table cell; the open proposal above carries the full
  # sentence.
  def claim_history_reason(%{direction: :grow, evidence: evidence}) do
    dgettext("dashboard", "discarding work after %{shed_age}, target %{floor}",
      shed_age: humanize_seconds(evidence["median_shed_age_seconds"]),
      floor: humanize_seconds(evidence["retention_floor_seconds"])
    )
  end

  def claim_history_reason(%{direction: :shrink, evidence: evidence}) do
    dgettext("dashboard", "peaked at %{peak}% of its disk", peak: evidence["max_occupancy_percent"])
  end

  defp kura_disk_usage_label(snapshot) do
    dgettext("dashboard", "%{used} of %{budget}",
      used: ByteFormatter.format_bytes(snapshot.live_segment_bytes),
      budget: ByteFormatter.format_bytes(snapshot.ring_budget_bytes)
    )
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
