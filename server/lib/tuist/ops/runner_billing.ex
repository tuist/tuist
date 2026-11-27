defmodule Tuist.Ops.RunnerBilling do
  @moduledoc """
  Audited, resumable activation of prepaid runner orders for Atlas, top-ups
  of a live pool (`top_up/3`), and audited starts and cancellations of runner
  trials (`update_trial/3`).

  An order paid in monthly instalments is activated in full on its start
  date with `instalments` and the first instalment's invoice: the whole
  balance is usable from the start, however many instalments are paid. The
  instalments are charged by their own Stripe subscription, marked with
  `tuist_runner_prepaid_instalments` metadata
  (`Tuist.Billing.prepaid_instalment_subscription?/1`), because the strict
  cutoff needs the runner subscription to carry nothing else.

  The request is committed before any external effect. A failed activation
  keeps its checkpoints and error; repeating the identical change resumes it.
  Stripe grants are also reconciled by activation metadata, beyond Stripe's
  24-hour idempotency window. Never roll back a successful grant merely because
  a later trial or schedule operation failed.

  An order that also prepays remote cache usage sets `covers_cache`: the pool's
  one grant then also pays for the cache usage Prices at the same multiplier,
  and the activation adds those Prices to the subscription when it lacks them
  (Enterprise carries none). Other pools cover runner usage only.
  """
  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Billing
  alias Tuist.Billing.CreditGrants
  alias Tuist.Billing.UsagePricing
  alias Tuist.Ops.RunnerTrialChange
  alias Tuist.Repo
  alias Tuist.Runners.Allowance
  alias Tuist.Runners.Billing, as: RunnerUsage
  alias Tuist.Runners.Prepaid
  alias Tuist.Runners.PrepaidActivation
  alias Tuist.Runners.PrepaidExpiry
  alias Tuist.Runners.PrepaidTopUp
  alias Tuist.Runners.Trials

  @fields ~w(paid_cents credit_multiplier platforms starts_on expires_on invoice_id expected_revision reason change_id actor interface)
  @trial_fields ~w(operation expected_revision reason change_id actor interface)
  @top_up_fields ~w(grants invoice_id expected_revision reason change_id actor interface)
  @platforms %{"macos" => :macos, "linux" => :linux}
  # Optional: `true` when the pool also pays for remote cache usage.
  @cache_field "covers_cache"

  def get(account_id) do
    with {:ok, account_id} <- account_id(account_id),
         %Account{} = account <- Repo.get(Account, account_id) do
      snapshot(account)
    else
      nil -> {:error, :resource_not_found}
      error -> error
    end
  end

  def activate(account_id, params, principal) do
    with {:ok, account_id} <- account_id(account_id),
         :ok <- validate(params),
         {:ok, activation} <- prepare(account_id, params, principal) do
      if activation.status == "applied", do: {:ok, activation.after}, else: run(activation)
    end
  end

  @doc """
  Starts or cancels the account's runner trial through `Tuist.Runners.Trials`,
  as the ops account page's trial buttons do, with the revision, reason,
  change UUID and replay contract of `Tuist.Ops.AccountPlans`. The revision is
  `get/1`'s, which covers the trial timestamps and the live subscription.

  Cancelling the trial of an account with no paid plan leaves it on Air, where
  the free runner allowance and cache caps apply again and its runner usage has
  no subscription to be billed on. That is refused with `:paid_plan_required`
  unless the request sets `confirm_air_limits`, so moving an account off its
  trial before it subscribes is a deliberate choice rather than a slip.

  `add_runner_items` adds the runner items to a Pro or Enterprise subscription
  that lacks them on an account that is not on a trial, through
  `Trials.start_billing/1`, so its runner usage is billable from then on. It is
  refused with `:on_trial` (cancel the trial instead), `:paid_plan_required`,
  or `:runner_items_present` when there is nothing to add.

  The change row is inserted before Stripe is called and the trial transition
  reconciles Stripe inside the same transaction, so a failed request records
  nothing and leaves the trial as it was.
  """
  def update_trial(account_id, params, principal) do
    with {:ok, account_id} <- account_id(account_id),
         :ok <- validate_trial(params) do
      Repo.transaction(
        fn ->
          account = locked_account(account_id)

          case Repo.get_by(RunnerTrialChange, change_id: params["change_id"]) do
            nil -> change_trial(account, params, principal)
            # An identical retry returns the recorded result, even after later changes.
            %RunnerTrialChange{account_id: ^account_id, request: ^params, after: after_state} -> after_state
            _ -> Repo.rollback(:change_id_conflict)
          end
        end,
        timeout: to_timeout(minute: 1)
      )
    end
  end

  defp change_trial(account, params, principal) do
    before = unwrap(snapshot(account))
    if before.revision != params["expected_revision"], do: Repo.rollback(:stale_revision)

    change =
      %{
        change_id: params["change_id"],
        account_id: account.id,
        request: params,
        principal: principal,
        before: json_map(before),
        after: %{}
      }
      |> RunnerTrialChange.create_changeset()
      |> Repo.insert()
      |> case do
        {:ok, change} -> change
        {:error, _changeset} -> Repo.rollback(:change_id_conflict)
      end

    account = transition_trial(params["operation"], account, params)
    # A trial change leaves credit grants alone, so they are not read again: a
    # failed read now would roll back a change Stripe has already applied.
    after_state = account |> snapshot(before.prepaid_grants) |> json_map()
    change |> Ecto.Changeset.change(after: after_state) |> Repo.update!()
    after_state
  end

  # Restarting a running trial would move its start to now and make the usage
  # it already covered read as billable.
  defp transition_trial("start", account, _params) do
    if Trials.on_trial?(account), do: Repo.rollback(:already_on_trial)
    account |> Trials.start() |> trial_result()
  end

  defp transition_trial("cancel", account, params) do
    if not Trials.on_trial?(account), do: Repo.rollback(:not_on_trial)

    if Billing.effective_plan(account) == :air and params["confirm_air_limits"] != true,
      do: Repo.rollback(:paid_plan_required)

    account |> Trials.cancel() |> trial_result()
  end

  # For a paid subscription that never got its runner items, such as one that
  # predates runner Prices on an account that was never on a trial.
  defp transition_trial("add_runner_items", account, _params) do
    if Billing.effective_plan(account) not in [:pro, :enterprise], do: Repo.rollback(:paid_plan_required)

    case Trials.start_billing(account) do
      {:ok, account} -> account
      {:error, reason} when reason in [:on_trial, :runner_items_present, :no_subscription] -> Repo.rollback(reason)
      {:error, _reason} -> Repo.rollback(:stripe_request_failed)
    end
  end

  # With the trial state checked above, a transition only fails in Stripe.
  defp trial_result({:ok, account}), do: account
  defp trial_result({:error, _reason}), do: Repo.rollback(:stripe_request_failed)

  @doc """
  Tops up the account's live pool: more credit, bought on the invoice
  `invoice_id`, usable through the pool's last day and expiring with it.

  `grants` lists one entry per platform, each with what was paid for it and
  its own credit multiplier, because a top-up can be priced differently per
  platform: each becomes a grant scoped to that platform's Prices. A grant
  cannot spend money at two multipliers, so a top-up that applies to several
  platforms at different rates has to be split between them when it is sold.
  Top-up grants are spent before the pool (`Tuist.Runners.Prepaid`). When the
  pool covers cache, the Linux grant covers the cache Prices too, at the
  Linux multiplier, since an order's cache rates follow its Linux ones; a
  top-up with no Linux grant adds no cache credit.

  Refused with `:no_live_pool` without an applied pool that runs past today,
  `:platform_not_in_pool` for a platform the pool does not cover,
  `:invoice_does_not_match` unless the invoice is the customer's, in USD,
  and its subtotal is what the grants were paid, and `:invoice_already_used`
  when an activation or another top-up already recorded that invoice.

  Same contract as `activate/3`: the request is committed before any grant,
  an identical retry resumes or returns the recorded result, and each
  platform's grant is checkpointed and reconciled by its metadata, so a
  resumed top-up never grants a platform twice. The pool's schedule already
  closes its last period, so nothing else changes in Stripe.
  """
  def top_up(account_id, params, principal) do
    with {:ok, account_id} <- account_id(account_id),
         :ok <- validate_top_up(params),
         {:ok, top_up} <- prepare_top_up(account_id, params, principal) do
      if top_up.status == "applied", do: {:ok, top_up.after}, else: run_top_up(top_up)
    end
  end

  defp prepare_top_up(account_id, params, principal) do
    Repo.transaction(
      fn ->
        account = locked_account(account_id)

        case Repo.get_by(PrepaidTopUp, change_id: params["change_id"]) do
          %PrepaidTopUp{account_id: ^account_id, request: ^params} = top_up ->
            top_up

          %PrepaidTopUp{} ->
            Repo.rollback(:change_id_conflict)

          nil ->
            if Repo.exists?(from(a in PrepaidActivation, where: a.change_id == ^params["change_id"])),
              do: Repo.rollback(:change_id_conflict)

            before = unwrap(snapshot(account))
            if before.revision != params["expected_revision"], do: Repo.rollback(:stale_revision)
            pool = live_pool(account_id) || Repo.rollback(:no_live_pool)
            unwrap(preflight_top_up(account, params, pool))

            %PrepaidTopUp{
              account_id: account_id,
              activation_id: pool.id,
              change_id: params["change_id"],
              request: params,
              principal: principal,
              before: json_map(before)
            }
            |> Ecto.Changeset.change()
            |> Ecto.Changeset.unique_constraint(:change_id)
            |> Repo.insert()
            |> case do
              {:ok, top_up} -> top_up
              {:error, _} -> Repo.rollback(:change_id_conflict)
            end
        end
      end,
      timeout: to_timeout(minute: 1)
    )
  end

  # A pool ending today has nothing left to top up: a grant expiring with it
  # could only pay for today.
  defp live_pool(account_id) do
    today = Date.utc_today()

    Repo.one(
      from(a in PrepaidActivation,
        where: a.account_id == ^account_id and a.status == "applied",
        where: fragment("(?->>'starts_on')::date <= ?", a.request, ^today),
        where: fragment("(?->>'expires_on')::date > ?", a.request, ^today),
        order_by: [desc: a.id],
        limit: 1
      )
    )
  end

  defp preflight_top_up(account, params, pool) do
    invoice_id = params["invoice_id"]
    paid_cents = params["grants"] |> Enum.map(& &1["paid_cents"]) |> Enum.sum()

    invoice_used? =
      Repo.exists?(
        from(a in PrepaidActivation,
          where: a.account_id == ^account.id and fragment("?->>'invoice_id'", a.request) == ^invoice_id
        )
      ) or
        Repo.exists?(
          from(t in PrepaidTopUp,
            where: t.account_id == ^account.id and fragment("?->>'invoice_id'", t.request) == ^invoice_id
          )
        )

    cond do
      Enum.any?(params["grants"], &(&1["platform"] not in pool.request["platforms"])) ->
        {:error, :platform_not_in_pool}

      invoice_used? ->
        {:error, :invoice_already_used}

      Enum.any?(params["grants"], &top_up_covers_cache?(pool, &1["platform"])) and
          match?({:error, _}, Prepaid.cache_price_ids()) ->
        {:error, :no_cache_prices_configured}

      true ->
        with {:ok, invoice} <- Stripe.Invoice.retrieve(invoice_id),
             :ok <- invoice_matches(invoice, account, paid_cents, 1),
             do: {:ok, :ready}
    end
  end

  defp run_top_up(top_up) do
    # Serialized like `run/1`, and for the same reason errors are returned
    # rather than rolled back: the checkpoints record grants Stripe accepted.
    case Repo.transaction(
           fn ->
             account = locked_account(top_up.account_id)
             top_up = PrepaidTopUp |> Repo.get!(top_up.id) |> Repo.preload(:activation)

             if top_up.status == "applied", do: {:ok, top_up.after}, else: resume_top_up(account, top_up)
           end,
           timeout: to_timeout(minute: 1)
         ) do
      {:ok, result} -> result
      error -> error
    end
  end

  defp resume_top_up(account, top_up) do
    with {:ok, top_up} <- grant_top_up(account, top_up),
         {:ok, state} <- snapshot(account) do
      top_up |> Ecto.Changeset.change(status: "applied", error: nil, after: json_map(state)) |> Repo.update!()
      {:ok, state}
    else
      {:error, _reason} ->
        PrepaidTopUp
        |> Repo.get!(top_up.id)
        |> Ecto.Changeset.change(status: "pending", error: "stripe_request_failed")
        |> Repo.update!()

        {:error, :stripe_request_failed}
    end
  end

  defp grant_top_up(account, top_up) do
    entries = top_up.request["grants"]

    if length(top_up.grant_ids) == length(entries) do
      {:ok, top_up}
    else
      with {:ok, grants} <- CreditGrants.list_for_customer(account.customer_id) do
        Enum.reduce_while(entries, {:ok, top_up}, &grant_top_up_entry(account, grants, &1, &2))
      end
    end
  end

  defp grant_top_up_entry(account, grants, entry, {:ok, top_up}) do
    case find_or_grant_top_up(account, top_up, entry, grants) do
      {:ok, %{id: id}} when is_binary(id) -> {:cont, {:ok, checkpoint_grant(top_up, id)}}
      error -> {:halt, error}
    end
  end

  # A top-up of a pool that covers cache buys cache at the Order's Linux
  # rate, so the Linux grant pays for the cache Prices too, at its own
  # multiplier. A top-up without a Linux grant leaves cache to the pool.
  defp top_up_covers_cache?(pool, platform), do: platform == "linux" and covers_cache?(pool.request)

  defp checkpoint_grant(top_up, grant_id) do
    if grant_id in top_up.grant_ids,
      do: top_up,
      else: top_up |> Ecto.Changeset.change(grant_ids: top_up.grant_ids ++ [grant_id]) |> Repo.update!()
  end

  defp find_or_grant_top_up(account, top_up, entry, grants) do
    platform = entry["platform"]

    case Enum.find(grants, fn grant ->
           metadata = metadata(grant)
           metadata["tuist_prepaid_activation_id"] == top_up.change_id and metadata["tuist_prepaid_platforms"] == platform
         end) do
      nil ->
        Prepaid.grant_pool(account, %{
          paid_cents: entry["paid_cents"],
          credit_multiplier: Decimal.new(entry["credit_multiplier"]),
          platforms: [Map.fetch!(@platforms, platform)],
          # The request's day rather than the attempt's, so every attempt
          # asks Stripe for the same grant.
          starts_on: DateTime.to_date(top_up.inserted_at),
          expires_on: expiry(top_up.activation.request),
          invoice_id: top_up.request["invoice_id"],
          activation_id: top_up.change_id,
          top_up_of: top_up.activation.change_id,
          covers_cache: top_up_covers_cache?(top_up.activation, platform)
        })

      grant ->
        {:ok, grant}
    end
  end

  defp prepare(account_id, params, principal) do
    Repo.transaction(
      fn ->
        account = locked_account(account_id)

        case Repo.get_by(PrepaidActivation, change_id: params["change_id"]) do
          %PrepaidActivation{account_id: ^account_id, request: ^params} = activation ->
            activation

          %PrepaidActivation{} ->
            Repo.rollback(:change_id_conflict)

          nil ->
            # Grants are reconciled by this UUID in their metadata, so it must
            # not name a top-up's grants too.
            if Repo.exists?(from(t in PrepaidTopUp, where: t.change_id == ^params["change_id"])),
              do: Repo.rollback(:change_id_conflict)

            before = unwrap(snapshot(account))
            if before.revision != params["expected_revision"], do: Repo.rollback(:stale_revision)
            unwrap(preflight(account, params, before))

            %PrepaidActivation{
              account_id: account_id,
              change_id: params["change_id"],
              request: params,
              principal: principal,
              before: json_map(before),
              activated_at: DateTime.truncate(DateTime.utc_now(), :second)
            }
            |> Ecto.Changeset.change()
            |> Ecto.Changeset.unique_constraint(:change_id)
            |> Repo.insert()
            |> case do
              {:ok, activation} -> activation
              {:error, _} -> Repo.rollback(:change_id_conflict)
            end
        end
      end,
      timeout: to_timeout(minute: 1)
    )
  end

  defp run(activation) do
    # Serializes concurrent resumes, including requests arriving on another
    # replica. Return errors normally: rolling back would erase checkpoints
    # for effects Stripe has already accepted.
    case Repo.transaction(
           fn ->
             account = locked_account(activation.account_id)
             activation = Repo.get!(PrepaidActivation, activation.id)
             resume(account, activation)
           end,
           timeout: to_timeout(minute: 1)
         ) do
      {:ok, result} -> result
      error -> error
    end
  end

  defp resume(_account, %PrepaidActivation{status: "applied"} = activation), do: {:ok, activation.after}

  defp resume(account, activation) do
    case apply_steps(account, activation) do
      {:ok, state} ->
        {:ok, state}

      {:error, _reason} ->
        activation
        |> Repo.reload!()
        |> Ecto.Changeset.change(status: "pending", error: "stripe_request_failed")
        |> Repo.update!()

        {:error, :stripe_request_failed}
    end
  end

  defp apply_steps(account, activation) do
    with {:ok, activation} <- grant(account, activation),
         {:ok, account} <- end_trial(account, activation),
         # Before the schedule, which copies the subscription's items.
         :ok <- add_cache_items(account, activation),
         {:ok, schedule_id} <-
           PrepaidExpiry.schedule(account, activation.change_id, expiry(activation.request),
             covers_cache: covers_cache?(activation.request)
           ) do
      activation =
        activation
        |> Ecto.Changeset.change(status: "applied", error: nil, subscription_schedule_id: schedule_id)
        |> Repo.update!()

      with {:ok, state} <- snapshot(account) do
        activation |> Ecto.Changeset.change(after: json_map(state)) |> Repo.update!()
        {:ok, state}
      end
    end
  end

  defp grant(_account, %PrepaidActivation{grant_id: id} = activation) when is_binary(id), do: {:ok, activation}

  defp grant(account, activation) do
    with {:ok, grants} <- CreditGrants.list_for_customer(account.customer_id),
         {:ok, grant} <- find_or_grant(account, activation, grants) do
      activation |> Ecto.Changeset.change(grant_id: grant.id) |> Repo.update()
    end
  end

  defp find_or_grant(account, activation, grants) do
    case Enum.find(grants, &(metadata(&1)["tuist_prepaid_activation_id"] == activation.change_id)) do
      nil ->
        params = activation.request

        with {:ok, instalment_subscription_id} <- instalment_subscription_id(params) do
          Prepaid.grant_pool(account, %{
            paid_cents: params["paid_cents"],
            credit_multiplier: Decimal.new(params["credit_multiplier"]),
            platforms: Enum.map(params["platforms"], &Map.fetch!(@platforms, &1)),
            starts_on: Date.from_iso8601!(params["starts_on"]),
            expires_on: expiry(params),
            invoice_id: params["invoice_id"],
            instalments: params["instalments"],
            instalment_subscription_id: instalment_subscription_id,
            activation_id: activation.change_id,
            covers_cache: covers_cache?(params)
          })
        end

      grant ->
        {:ok, grant}
    end
  end

  # An Enterprise subscription carries no cache usage Prices, so without them
  # cache usage is never invoiced and the pool has no cache usage to pay for.
  # Added without proration, like the runner items, so usage before the
  # activation is not invoiced.
  defp add_cache_items(account, activation) do
    if covers_cache?(activation.request), do: put_cache_items(account), else: :ok
  end

  defp put_cache_items(account) do
    with {:ok, price_ids} <- Prepaid.cache_price_ids(),
         {:ok, subscription} <- PrepaidExpiry.subscription(account) do
      present = Enum.map(subscription.items.data, & &1.price.id)

      case Enum.reject(price_ids, &(&1 in present)) do
        [] ->
          :ok

        missing ->
          subscription.id
          |> Stripe.Subscription.update(%{items: Enum.map(missing, &%{price: &1}), proration_behavior: "none"})
          |> then(fn
            {:ok, _subscription} -> :ok
            error -> error
          end)
      end
    end
  end

  defp covers_cache?(params), do: Map.get(params, @cache_field) == true

  defp end_trial(account, activation) do
    if Trials.on_trial?(account),
      do: Trials.cancel(account, activation.activated_at),
      else:
        account
        |> Billing.sync_runner_subscription_items()
        |> then(fn
          {:ok, _} -> {:ok, account}
          error -> error
        end)
  end

  defp preflight(account, params, before) do
    today = Date.utc_today()
    expires_on = expiry(params)
    starts_on = Date.from_iso8601!(params["starts_on"])

    overlapping? =
      Repo.exists?(
        from(a in PrepaidActivation,
          where: a.account_id == ^account.id,
          where: fragment("(?->>'expires_on')::date >= ?", a.request, ^today)
        )
      ) or Enum.any?(before.prepaid_grants, &(&1.available_cents > 0 and live?(&1)))

    cond do
      is_nil(account.customer_id) ->
        {:error, :stripe_customer_required}

      Date.after?(starts_on, today) or not Date.after?(expires_on, today) or
          Date.after?(Date.add(expires_on, 1), Date.shift(starts_on, year: 1)) ->
        {:error, :invalid_term}

      overlapping? ->
        {:error, :prepaid_pool_exists}

      true ->
        with {:ok, subscription} <- PrepaidExpiry.subscription(account),
             :ok <- PrepaidExpiry.validate(subscription, params["change_id"], covers_cache: covers_cache?(params)),
             {:ok, invoice} <- Stripe.Invoice.retrieve(params["invoice_id"]),
             :ok <- invoice_matches(invoice, account, params["paid_cents"], params["instalments"]),
             :ok <- validate_instalments(invoice, account, subscription, params["instalments"]),
             :ok <- validate_prices(params["platforms"]),
             :ok <- validate_cache_prices(params) do
          {:ok, :ready}
        end
    end
  end

  # With instalments, `invoice` is the first one's, so it carries an equal
  # share of the order.
  defp invoice_matches(invoice, account, paid_cents, nil), do: invoice_matches(invoice, account, paid_cents, 1)

  defp invoice_matches(invoice, account, paid_cents, instalments) do
    if invoice.customer == account.customer_id and invoice.currency == "usd" and
         invoice.subtotal * instalments == paid_cents and invoice.status in ~w(draft open paid),
       do: :ok,
       else: {:error, :invoice_does_not_match}
  end

  # The instalment invoice must come from a subscription of its own, marked
  # as one, so the subscription webhooks leave it out of the account's plan
  # and it never touches the runner subscription the cutoff is scheduled on.
  defp validate_instalments(_invoice, _account, _runner_subscription, nil), do: :ok

  defp validate_instalments(invoice, account, runner_subscription, _instalments) do
    with id when is_binary(id) and id != runner_subscription.id <- object_id(Map.get(invoice, :subscription)),
         {:ok, subscription} <- Stripe.Subscription.retrieve(id),
         true <- subscription.customer == account.customer_id,
         true <- Billing.prepaid_instalment_subscription?(subscription) do
      :ok
    else
      {:error, _reason} = error -> error
      _ -> {:error, :instalment_subscription_required}
    end
  end

  defp instalment_subscription_id(%{"instalments" => instalments} = params) when is_integer(instalments) do
    with {:ok, invoice} <- Stripe.Invoice.retrieve(params["invoice_id"]),
         do: {:ok, object_id(Map.get(invoice, :subscription))}
  end

  defp instalment_subscription_id(_params), do: {:ok, nil}

  defp validate_prices(platforms) do
    prices = Map.get(Tuist.Environment.stripe_prices() || %{}, "runners", %{})

    Enum.reduce_while(platforms, :ok, fn platform, :ok ->
      platform = Map.fetch!(@platforms, platform)
      price_id = Map.get(prices, RunnerUsage.meter_event_name(platform))
      rate = Decimal.div(Prepaid.on_demand_cost_for_milliseconds(platform, 6_000_000).amount, 6_000_000)
      tiers = {Allowance.free_monthly_minutes(platform) * 60_000, rate}

      case validate_price(price_id, tiers, {:no_runner_prices_configured, :runner_price_mismatch}) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  # Cache usage is reported gross at the list rates `UsagePricing` quotes, as
  # runner usage is at the on-demand rate, and the multiplier discounts both.
  defp validate_cache_prices(params) do
    if covers_cache?(params), do: validate_cache_prices(), else: :ok
  end

  defp validate_cache_prices do
    prices = Map.get(Tuist.Environment.stripe_prices() || %{}, "usage_meters", %{})

    UsagePricing.meter_prices()
    |> Enum.filter(&(&1.event_name in Prepaid.cache_meters()))
    |> Enum.reduce_while(:ok, fn meter, :ok ->
      tiers = {meter.included, Decimal.div(meter.cents, meter.per_units)}

      case validate_price(prices[meter.event_name], tiers, {:no_cache_prices_configured, :cache_price_mismatch}) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_price(price_id, tiers, {_missing, mismatch}) when is_binary(price_id) and price_id != "" do
    with {:ok, price} <- Stripe.Price.retrieve(price_id, %{expand: ["tiers"]}) do
      if correct_price?(price, tiers), do: :ok, else: {:error, mismatch}
    end
  end

  defp validate_price(_price_id, _tiers, {missing, _mismatch}), do: {:error, missing}

  defp correct_price?(
         %{
           currency: "usd",
           billing_scheme: "tiered",
           tiers_mode: "graduated",
           recurring: %{interval: "month", interval_count: 1, usage_type: "metered"},
           tiers: [free, paid]
         },
         {free_up_to, expected_rate}
       ) do
    rate = Decimal.new(Map.get(paid, :unit_amount_decimal) || to_string(Map.get(paid, :unit_amount, 0)))

    free.up_to == free_up_to and zero?(free, :unit_amount) and
      zero?(free, :flat_amount) and zero?(paid, :flat_amount) and is_nil(paid.up_to) and
      Decimal.compare(Decimal.abs(Decimal.sub(rate, expected_rate)), Decimal.new("0.000000000001")) != :gt
  end

  defp correct_price?(_price, _tiers), do: false

  defp zero?(tier, key) do
    decimal_key = if key == :unit_amount, do: :unit_amount_decimal, else: :flat_amount_decimal
    Decimal.equal?(Decimal.new(Map.get(tier, decimal_key) || Map.get(tier, key) || 0), 0)
  end

  defp snapshot(account) do
    with {:ok, grants} <- grants(account), do: {:ok, snapshot(account, grants)}
  end

  defp snapshot(account, grants) do
    activation =
      Repo.one(from(a in PrepaidActivation, where: a.account_id == ^account.id, order_by: [desc: a.id], limit: 1))

    subscription = Billing.get_current_active_subscription(account)

    state = %{
      account_id: account.id,
      account_handle: account.name,
      stripe_customer_id: account.customer_id,
      runner_trial: %{
        active: Trials.on_trial?(account),
        started_at: account.runner_trial_started_at,
        ended_at: account.runner_trial_ended_at
      },
      prepaid_grants: grants,
      activation: activation && activation_json(activation)
    }

    revision =
      {json_map(state), subscription && {subscription.subscription_id, subscription.status, subscription.updated_at}}
      # Timestamp struct keys can have different internal atom orders on each replica.
      |> :erlang.term_to_binary([:deterministic])
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    Map.put(state, :revision, revision)
  end

  defp grants(%Account{customer_id: nil}), do: {:ok, []}

  defp grants(account) do
    case CreditGrants.list_for_customer(account.customer_id) do
      {:ok, grants} ->
        grants
        |> Enum.filter(&(metadata(&1)["tuist_runner_credit"] in ~w(pool prepaid trial)))
        |> Enum.reduce_while({:ok, []}, fn grant, {:ok, acc} ->
          case CreditGrants.available_balance_cents(account.customer_id, grant.id) do
            {:ok, available} ->
              data = %{
                id: grant.id,
                currency: grant.amount.monetary.currency,
                amount_cents: grant.amount.monetary.value,
                available_cents: available,
                expires_at: unix_datetime(Map.get(grant, :expires_at)),
                metadata: metadata(grant)
              }

              {:cont, {:ok, [data | acc]}}

            {:error, _} ->
              {:halt, {:error, :stripe_request_failed}}
          end
        end)
        |> case do
          {:ok, grants} -> {:ok, Enum.sort_by(grants, & &1.id)}
          error -> error
        end

      {:error, _} ->
        {:error, :stripe_request_failed}
    end
  end

  defp activation_json(activation) do
    Map.merge(Map.take(activation, [:change_id, :status, :error, :grant_id, :subscription_schedule_id]), %{
      starts_on: activation.request["starts_on"],
      expires_on: activation.request["expires_on"],
      platforms: activation.request["platforms"],
      paid_cents: activation.request["paid_cents"],
      credit_multiplier: activation.request["credit_multiplier"]
    })
  end

  # `instalments` is optional: an order paid up front leaves it out.
  defp validate(params) when is_map(params) do
    with true <- Enum.sort(Map.keys(params) -- [@cache_field, "instalments"]) == Enum.sort(@fields),
         true <-
           not Map.has_key?(params, "instalments") or
             (is_integer(params["instalments"]) and params["instalments"] in 2..12),
         true <- is_integer(params["paid_cents"]) and params["paid_cents"] > 0,
         true <- is_boolean(Map.get(params, @cache_field, false)),
         multiplier when is_binary(multiplier) and byte_size(multiplier) <= 20 <- params["credit_multiplier"],
         {multiplier, ""} <- Decimal.parse(multiplier),
         {:ok, _} <- Prepaid.quote_pool(params["paid_cents"], multiplier),
         platforms when is_list(platforms) and platforms != [] <- params["platforms"],
         true <- Enum.all?(platforms, &Map.has_key?(@platforms, &1)) and Enum.uniq(platforms) == platforms,
         true <- is_binary(params["starts_on"]) and byte_size(params["starts_on"]) == 10,
         true <- is_binary(params["expires_on"]) and byte_size(params["expires_on"]) == 10,
         {:ok, _} <- Date.from_iso8601(params["starts_on"]),
         {:ok, _} <- Date.from_iso8601(params["expires_on"]),
         true <- invoice_id?(params["invoice_id"]),
         true <- change?(params) do
      :ok
    else
      _ -> {:error, :invalid_request}
    end
  end

  defp validate(_), do: {:error, :invalid_request}

  defp validate_top_up(params) when is_map(params) do
    with true <- Enum.sort(Map.keys(params)) == Enum.sort(@top_up_fields),
         grants when is_list(grants) and grants != [] <- params["grants"],
         true <- Enum.all?(grants, &top_up_grant?/1),
         platforms = Enum.map(grants, & &1["platform"]),
         true <- Enum.uniq(platforms) == platforms,
         true <- invoice_id?(params["invoice_id"]),
         true <- change?(params) do
      :ok
    else
      _ -> {:error, :invalid_request}
    end
  end

  defp validate_top_up(_), do: {:error, :invalid_request}

  defp top_up_grant?(%{"platform" => platform, "paid_cents" => paid_cents, "credit_multiplier" => multiplier} = grant)
       when map_size(grant) == 3 and is_binary(multiplier) and byte_size(multiplier) <= 20 do
    with true <- Map.has_key?(@platforms, platform),
         {multiplier, ""} <- Decimal.parse(multiplier),
         {:ok, _} <- Prepaid.quote_pool(paid_cents, multiplier) do
      true
    else
      _ -> false
    end
  end

  defp top_up_grant?(_grant), do: false

  defp invoice_id?("in_" <> invoice), do: byte_size(invoice) > 0 and byte_size(invoice) < 255
  defp invoice_id?(_invoice_id), do: false

  # The revision, reason, change UUID, actor and interface every change carries.
  defp change?(params) do
    with true <- text?(params["expected_revision"], 64) and byte_size(params["expected_revision"]) == 64,
         true <- text?(params["reason"], 1000),
         {:ok, _} <- Ecto.UUID.cast(params["change_id"]),
         %{"id" => actor_id, "email" => email} = actor when map_size(actor) == 2 <- params["actor"],
         {:ok, _} <- Ecto.UUID.cast(actor_id),
         true <- text?(email, 320) do
      params["interface"] == "mcp"
    else
      _ -> false
    end
  end

  # `confirm_air_limits` is optional and only means anything to a cancel.
  defp validate_trial(params) when is_map(params) do
    with true <- Enum.sort(Map.keys(params) -- ["confirm_air_limits"]) == Enum.sort(@trial_fields),
         true <- params["operation"] in ~w(start cancel add_runner_items),
         true <-
           not Map.has_key?(params, "confirm_air_limits") or
             (params["operation"] == "cancel" and is_boolean(params["confirm_air_limits"])),
         true <- change?(params) do
      :ok
    else
      _ -> {:error, :invalid_request}
    end
  end

  defp validate_trial(_), do: {:error, :invalid_request}
  defp text?(value, max), do: is_binary(value) and byte_size(value) <= max and String.trim(value) != ""
  defp expiry(params), do: Date.from_iso8601!(params["expires_on"])
  defp object_id(%{id: id}), do: id
  defp object_id(id), do: id
  defp metadata(grant), do: Map.new(Map.get(grant, :metadata) || %{}, fn {k, v} -> {to_string(k), v} end)
  defp live?(%{expires_at: nil}), do: true
  defp live?(%{expires_at: expires_at}), do: DateTime.after?(expires_at, DateTime.utc_now())
  defp unix_datetime(nil), do: nil
  defp unix_datetime(unix), do: DateTime.from_unix!(unix)
  defp json_map(value), do: value |> JSON.encode!() |> JSON.decode!()
  defp unwrap({:ok, result}), do: result
  defp unwrap({:error, reason}), do: Repo.rollback(if(is_atom(reason), do: reason, else: :stripe_request_failed))

  defp locked_account(id),
    do: Repo.one(from(a in Account, where: a.id == ^id, lock: "FOR UPDATE")) || Repo.rollback(:resource_not_found)

  defp account_id(id) when is_integer(id) and id > 0 and id <= 9_223_372_036_854_775_807, do: {:ok, id}

  defp account_id(id) when is_binary(id) and byte_size(id) in 1..19 do
    case Integer.parse(id) do
      {id, ""} -> account_id(id)
      _ -> {:error, :invalid_target}
    end
  end

  defp account_id(_), do: {:error, :invalid_target}
end
