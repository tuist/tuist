defmodule TuistWeb.OpsAccountLive do
  @moduledoc """
  Account detail page in /ops. The hub for everything an operator does
  on a single account: plan / billing actions (Stripe, Enterprise upgrade,
  cancel), and Kura placement — which region the account's cache resolves to,
  and which instances it actually holds.

  Every write on this page is gated by the `/ops` live session's
  `{TuistWeb.Authorization, [:current_user, :read, :ops]}` mount, which resolves
  to `internal_ops_access`: is this person Tuist staff. The Kura writes sit
  behind that same gate rather than `ops_write_access` on purpose.
  `ops_write_access` is the customer-data grant — an `:admin`-tier operator
  grant minted per account behind a Slack approval — and it is exactly the
  round trip the hand-written `bin/tuist eval` job this section replaces had to
  make. Requiring it here would reintroduce the second approver for an action
  that reads no customer data and writes only placement policy, which is the
  reason the assignment had no repeatable surface in the first place.
  """
  use TuistWeb, :live_view
  use Noora

  import Ecto.Query, only: [from: 2]
  import TuistWeb.OpsAccountHelpers

  alias Tuist.Accounts
  alias Tuist.Billing
  alias Tuist.Billing.Subscription
  alias Tuist.Kura
  alias Tuist.Kura.AccountPolicies
  alias Tuist.Kura.AccountRegionPolicy
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Server
  alias Tuist.Repo
  alias Tuist.Runners.Concurrency
  alias Tuist.Runners.Prepaid
  alias Tuist.Runners.Trials
  alias Tuist.Utilities.DateFormatter

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Accounts.get_account_by_id(parse_id(id)) do
      {:ok, account} ->
        account = preload_billing(account)
        if connected?(socket), do: Kura.subscribe_to_account(account.id)
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
         |> assign(:restore_target, nil)
         |> assign_kura(account)
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
  def handle_event("update_kura_storage_claim", %{"account" => params}, socket) do
    account = socket.assigns.account

    case Kura.update_storage_claim_override(account, params) do
      {:ok, result} ->
        {:noreply,
         socket
         |> assign_kura(account)
         |> put_flash(:info, kura_storage_claim_message(result))}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:kura_storage_claim_form, to_form(changeset, as: "account"))
         |> put_flash(:error, dgettext("dashboard", "Kura disk claim could not be updated."))}
    end
  end

  ## Kura placement & instance event handlers

  @impl true
  def handle_event("assign_kura_service_region", %{"assignment" => params}, socket) do
    account = socket.assigns.account

    # The submitted region is handed to the domain unchecked on purpose: the
    # picker is rendered from `AccountRegionPolicy.service_regions/0`, which is
    # the same list `validate_explicit_assignment/2` accepts, so a crafted event
    # naming anything else is refused there rather than needing a second guard
    # here that could drift from it.
    case AccountPolicies.assign_service_region(
           account,
           params["service_region"],
           socket.assigns.current_user,
           params["reason"] || ""
         ) do
      {:ok, assignment} ->
        {:noreply,
         socket
         |> assign_kura(account)
         |> put_flash(:info, assignment_message(account, assignment))}

      {:error, reason} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("dashboard", "Could not assign a service region: %{reason}", reason: assignment_error_message(reason))
         )}
    end
  end

  @impl true
  def handle_event("open_restore_kura_assignment", %{"version" => version}, socket) do
    case Enum.find(socket.assigns.kura_assignment_history, &(to_string(&1.version) == version)) do
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("dashboard", "That assignment no longer exists."))}

      %AccountRegionPolicy{} = assignment ->
        {:noreply,
         socket
         |> assign(:restore_target, assignment)
         |> push_event("open-modal", %{id: "restore-assignment-modal"})}
    end
  end

  @impl true
  def handle_event("close_restore_kura_assignment", _params, socket) do
    {:noreply,
     socket
     |> assign(:restore_target, nil)
     |> push_event("close-modal", %{id: "restore-assignment-modal"})}
  end

  @impl true
  def handle_event("restore_kura_assignment", %{"assignment" => params}, socket) do
    account = socket.assigns.account

    case AccountPolicies.restore_service_region(
           account,
           parse_version(params["version"]),
           socket.assigns.current_user,
           params["reason"] || ""
         ) do
      {:ok, assignment} ->
        {:noreply,
         socket
         |> assign(:restore_target, nil)
         |> assign_kura(account)
         |> push_event("close-modal", %{id: "restore-assignment-modal"})
         |> put_flash(:info, assignment_message(account, assignment))}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:restore_target, nil)
         |> push_event("close-modal", %{id: "restore-assignment-modal"})
         |> put_flash(
           :error,
           dgettext("dashboard", "Could not restore that assignment: %{reason}", reason: assignment_error_message(reason))
         )}
    end
  end

  @impl true
  def handle_event("provision_kura_instance", %{"instance" => params}, socket) do
    account = socket.assigns.account

    case {provision_region(params, socket.assigns.kura_provision_regions), socket.assigns.kura_latest_version} do
      {nil, _} ->
        {:noreply, put_flash(socket, :error, dgettext("dashboard", "Pick a region this account can be provisioned in."))}

      {_region, nil} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext(
             "dashboard",
             "No Kura runtime image is configured right now. Try again after the next server deploy."
           )
         )}

      {region, version} ->
        provision_kura_instance(socket, %{
          account_id: account.id,
          region: region,
          image_tag: version_image_tag(version)
        })
    end
  end

  @impl true
  def handle_event("destroy_kura_instance", %{"id" => id}, socket) do
    account = socket.assigns.account

    case Kura.get_server(account.id, id) do
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("dashboard", "That Kura instance no longer exists."))}

      %Server{} = server ->
        case Kura.destroy_server(server) do
          {:ok, server} ->
            {:noreply,
             socket
             |> assign_kura(account)
             |> put_flash(
               :info,
               dgettext(
                 "dashboard",
                 "Destroying the Kura instance in %{region}. It stops serving now; the reconciler removes the backing resource and marks the row destroyed.",
                 region: server.region
               )
             )}

          {:error, reason} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               dgettext("dashboard", "Could not destroy the Kura instance: %{reason}", reason: inspect(reason))
             )}
        end
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

  # A provision or destroy anywhere else — the reconciler activating an instance,
  # the lifecycle archiving one — lands on this page too, so the table an
  # operator is watching after pressing Destroy reaches `destroyed` on its own.
  @impl true
  def handle_info({:kura_server, _event, _server}, socket) do
    {:noreply, assign_kura(socket, socket.assigns.account)}
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

  # Everything the two Kura cards read is re-derived in one place. They move on
  # the same writes: an override re-pins instances, so a table left on the old
  # assign would show claims that no longer exist; an assignment changes what
  # the account resolves to; a destroy frees its region back into the
  # provisioning picker. Re-deriving them apiece is how one of them ends up
  # describing state that is already gone.
  defp assign_kura(socket, account) do
    resolution = AccountPolicies.resolve(account)
    servers = Kura.list_servers_for_account(account.id)
    provision_regions = provision_regions(servers)

    socket
    |> assign(:kura_resolution, resolution)
    |> assign(:kura_assignment, AccountPolicies.current_service_region_assignment(account))
    |> assign(:kura_assignment_history, assignment_history(account))
    |> assign(:kura_assignment_refusal, assignment_refusal(account))
    |> assign(:kura_assignment_form, assignment_form(resolution))
    |> assign(:kura_servers, servers)
    |> assign(:kura_provision_regions, provision_regions)
    |> assign(:kura_latest_version, List.first(Kura.latest_versions(1)))
    |> assign(:kura_provision_form, provision_form(provision_regions, resolution))
    |> assign(:kura_account_claim, Kura.effective_storage_claim(account))
    |> assign(:kura_plan_claim, Kura.plan_storage_claim(account))
    |> assign(:kura_storage_claim_form, kura_storage_claim_form(account))
  end

  # The actor is what makes the row an audit trail rather than a log line, and
  # `list_service_region_history/1` returns the association unloaded.
  defp assignment_history(account) do
    account
    |> AccountPolicies.list_service_region_history()
    |> Repo.preload(:assigned_by_user)
  end

  # Mirrors `AccountPolicies.validate_explicit_assignment/2` so the card can say
  # why an assignment is impossible instead of rendering a form that can only
  # fail. Its third refusal, `:service_region_unavailable`, has no mirror here:
  # the picker is rendered from `AccountRegionPolicy.service_regions/0`, which is
  # the list that check accepts.
  defp assignment_refusal(account) do
    cond do
      Billing.effective_plan(account) not in [:pro, :enterprise] -> :plan_not_supported
      account.region != :all -> :service_region_is_derived
      true -> nil
    end
  end

  defp assignment_form(resolution) do
    to_form(%{"service_region" => default_assignable_region(resolution), "reason" => ""}, as: :assignment)
  end

  # Start the picker on the region the account resolves to today, so what the
  # operator submits reads as a change from what is in effect rather than from
  # whichever entry happens to be first.
  defp default_assignable_region({:ok, %{service_region: service_region}}) do
    if service_region in AccountRegionPolicy.service_regions(),
      do: service_region,
      else: List.first(AccountRegionPolicy.service_regions())
  end

  defp default_assignable_region(_resolution), do: List.first(AccountRegionPolicy.service_regions())

  # A region already holding a row for this account is not offered: the partial
  # uniqueness index counts a draining or archived row as owning
  # `(account, region)`, so a second instance there fails to insert rather than
  # returning the account to the region. Private runner-cache regions are left
  # out for the reason the customer-facing picker leaves them out — the identity
  # rule in `Tuist.Kura.RunnerCache` owns them, and adding one by hand only
  # fights the reconciler.
  defp provision_regions(servers) do
    occupied = MapSet.new(servers, & &1.region)
    Enum.reject(Regions.selectable(), &MapSet.member?(occupied, &1.id))
  end

  defp provision_form(regions, resolution) do
    to_form(%{"region" => default_provision_region(regions, resolution)}, as: :instance)
  end

  # Default to the region the account resolves to while it is still free, so an
  # instance added right after an assignment lands where the assignment sent it.
  defp default_provision_region(regions, {:ok, %{service_region: service_region}}) do
    if Enum.any?(regions, &(&1.id == service_region)),
      do: service_region,
      else: first_region_id(regions)
  end

  defp default_provision_region(regions, _resolution), do: first_region_id(regions)

  defp first_region_id([region | _]), do: region.id
  defp first_region_id([]), do: nil

  # Params are client-controlled and `Kura.create_server/1` accepts every region
  # in `Regions.available/0`, which is wider than what this card offers, so only
  # a region actually on the picker is honoured.
  defp provision_region(params, regions) do
    region = params["region"]
    if Enum.any?(regions, &(&1.id == region)), do: region
  end

  defp version_image_tag(%{image_tag: image_tag}), do: image_tag
  defp version_image_tag(%{version: "kura@" <> image_tag}), do: image_tag
  defp version_image_tag(%{version: image_tag}), do: image_tag

  defp parse_version(version) when is_binary(version) do
    case Integer.parse(version) do
      {parsed, ""} -> parsed
      _ -> 0
    end
  end

  defp parse_version(_version), do: 0

  defp provision_kura_instance(socket, attrs) do
    case Kura.create_server(attrs) do
      {:ok, server} ->
        {:noreply,
         socket
         |> assign_kura(socket.assigns.account)
         |> put_flash(
           :info,
           dgettext("dashboard", "Provisioning a Kura instance in %{region}.", region: server.region)
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("dashboard", "Could not provision a Kura instance: %{reason}", reason: format_errors(changeset))
         )}

      {:error, reason} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("dashboard", "Could not provision a Kura instance: %{reason}", reason: inspect(reason))
         )}
    end
  end

  defp format_errors(%Ecto.Changeset{errors: errors}) do
    Enum.map_join(errors, ", ", fn {field, {message, _opts}} -> "#{field} #{message}" end)
  end

  # Says what the assignment did and, just as importantly, what it did not do.
  # `Lifecycle.account_regions_needing_instance/3` honours a destroy only while
  # the destroyed row is newer than the account's last recorded cache demand, so
  # a destroy that lands before the demand it was meant to redirect is undone by
  # that demand and the instance comes back in the region that was just cleared.
  defp assignment_message(account, %AccountRegionPolicy{} = assignment) do
    dgettext(
      "dashboard",
      "%{account} is assigned to %{region} as version %{version}. The lifecycle provisions an instance there on the next cache demand; destroy the one in the old region only once that has happened.",
      account: account.name,
      region: assignment.service_region,
      version: assignment.version
    )
  end

  ## Kura view helpers

  def assignment_error_message(:plan_not_supported) do
    dgettext("dashboard", "only Pro and Enterprise accounts can be assigned a service region.")
  end

  def assignment_error_message(:service_region_is_derived) do
    dgettext(
      "dashboard",
      "this account named a storage region, so its service region is derived from it and cannot be overridden."
    )
  end

  def assignment_error_message(:service_region_unavailable) do
    dgettext("dashboard", "that is not a region an account can be assigned to.")
  end

  def assignment_error_message(:assignment_not_found) do
    dgettext("dashboard", "that version is not in this account's assignment history.")
  end

  def assignment_error_message(:account_not_found), do: dgettext("dashboard", "the account no longer exists.")

  def assignment_error_message(:invalid_assignment) do
    dgettext("dashboard", "the submitted assignment was incomplete.")
  end

  def assignment_error_message(%Ecto.Changeset{} = changeset), do: format_errors(changeset)

  def assignment_error_message(reason), do: inspect(reason)

  def assignment_refusal_message(:plan_not_supported, account) do
    dgettext(
      "dashboard",
      "Only Pro and Enterprise accounts can be assigned a service region, and this one is on %{plan}. Air resolves from its storage region alone, and Open Source has no Kura pool behind it at all, so neither is correctable here: the route is a plan change or a storage-region change.",
      plan: effective_plan_label(account)
    )
  end

  def assignment_refusal_message(:service_region_is_derived, account) do
    dgettext(
      "dashboard",
      "This account's storage region is %{region}, so its service region is derived from that and must not be overridden here. Set the storage region back to all regions first if it should be pinned explicitly.",
      region: storage_region_label(account.region)
    )
  end

  def resolved_service_region({:ok, %{service_region: service_region}}, _assignment), do: region_label(service_region)

  # An assignment may name a region this deployment does not serve yet: the two
  # gates are separate on purpose, and `AccountPolicies` refuses rather than
  # falling back to the default, because silently relocating an explicitly
  # assigned account is what an assignment exists to prevent. Say that, rather
  # than reporting it as a storage region with no pool behind it.
  def resolved_service_region({:error, :service_region_unavailable}, %AccountRegionPolicy{} = assignment) do
    dgettext(
      "dashboard",
      "Unresolved — %{region} is assigned but this deployment does not serve it yet. The assignment stands and resolves once the region is brought up.",
      region: region_label(assignment.service_region)
    )
  end

  def resolved_service_region({:error, reason}, _assignment) do
    dgettext("dashboard", "Unresolved — %{reason}", reason: resolution_error_message(reason))
  end

  # `:plan_not_supported` reaches this page from two different checks and means
  # something different in each. Out of `resolve/1` it is the Open Source plan,
  # which has no Kura pool behind it at all; out of the assignment check it is
  # any plan that is not Pro or Enterprise, Air included. They do not share copy.
  def resolution_error_message(:plan_not_supported) do
    dgettext("dashboard", "this account is on a plan no Kura pool serves.")
  end

  def resolution_error_message(:service_region_unavailable) do
    dgettext("dashboard", "no Kura region serves this account's storage region.")
  end

  def resolution_error_message(reason), do: inspect(reason)

  def effective_plan_label(account), do: account |> Billing.effective_plan() |> plan_label()

  def region_label(region_id) do
    case Regions.get(region_id) do
      nil -> region_id
      region -> "#{region.display_name} (#{region.id})"
    end
  end

  def storage_region_label(:all), do: dgettext("dashboard", "All regions")
  def storage_region_label(:europe), do: dgettext("dashboard", "Europe")
  def storage_region_label(:usa), do: dgettext("dashboard", "United States")
  def storage_region_label(region), do: to_string(region)

  def assignment_actor(%AccountRegionPolicy{assigned_by_user: %{email: email}}), do: email
  def assignment_actor(_assignment), do: dgettext("dashboard", "Unknown")

  def assignment_timestamp(%DateTime{} = at), do: DateFormatter.format_iso(at)
  def assignment_timestamp(_at), do: dgettext("dashboard", "None")

  def instance_status_label(status), do: status |> Atom.to_string() |> String.replace("_", " ")

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
