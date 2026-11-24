defmodule Tuist.Ops.RunnerBilling do
  @moduledoc """
  Audited, resumable activation of prepaid runner orders for Atlas, and
  audited starts and cancellations of runner trials (`update_trial/3`).

  The request is committed before any external effect. A failed activation
  keeps its checkpoints and error; repeating the identical change resumes it.
  Stripe grants are also reconciled by activation metadata, beyond Stripe's
  24-hour idempotency window. Never roll back a successful grant merely because
  a later trial or schedule operation failed.
  """
  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Billing
  alias Tuist.Billing.CreditGrants
  alias Tuist.Ops.RunnerTrialChange
  alias Tuist.Repo
  alias Tuist.Runners.Allowance
  alias Tuist.Runners.Billing, as: RunnerUsage
  alias Tuist.Runners.Prepaid
  alias Tuist.Runners.PrepaidActivation
  alias Tuist.Runners.PrepaidExpiry
  alias Tuist.Runners.Trials

  @fields ~w(paid_cents credit_multiplier platforms starts_on expires_on invoice_id expected_revision reason change_id actor interface)
  @trial_fields ~w(operation expected_revision reason change_id actor interface)
  @platforms %{"macos" => :macos, "linux" => :linux}

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

  # With the trial state checked above, a transition only fails in Stripe.
  defp trial_result({:ok, account}), do: account
  defp trial_result({:error, _reason}), do: Repo.rollback(:stripe_request_failed)

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
         {:ok, schedule_id} <- PrepaidExpiry.schedule(account, activation.change_id, expiry(activation.request)) do
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

        Prepaid.grant_pool(account, %{
          paid_cents: params["paid_cents"],
          credit_multiplier: Decimal.new(params["credit_multiplier"]),
          platforms: Enum.map(params["platforms"], &Map.fetch!(@platforms, &1)),
          starts_on: Date.from_iso8601!(params["starts_on"]),
          expires_on: expiry(params),
          invoice_id: params["invoice_id"],
          activation_id: activation.change_id
        })

      grant ->
        {:ok, grant}
    end
  end

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
             :ok <- PrepaidExpiry.validate(subscription, params["change_id"]),
             {:ok, invoice} <- Stripe.Invoice.retrieve(params["invoice_id"]),
             :ok <- invoice_matches(invoice, account, params),
             :ok <- validate_prices(params["platforms"]) do
          {:ok, :ready}
        end
    end
  end

  defp invoice_matches(invoice, account, params) do
    if invoice.customer == account.customer_id and invoice.currency == "usd" and
         invoice.subtotal == params["paid_cents"] and invoice.status in ~w(draft open paid),
       do: :ok,
       else: {:error, :invoice_does_not_match}
  end

  defp validate_prices(platforms) do
    prices = Map.get(Tuist.Environment.stripe_prices() || %{}, "runners", %{})

    Enum.reduce_while(platforms, :ok, fn platform, :ok ->
      platform = Map.fetch!(@platforms, platform)
      price_id = Map.get(prices, RunnerUsage.meter_event_name(platform))

      case validate_price(price_id, platform) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_price(price_id, platform) when is_binary(price_id) and price_id != "" do
    with {:ok, price} <- Stripe.Price.retrieve(price_id, %{expand: ["tiers"]}) do
      if correct_price?(price, platform), do: :ok, else: {:error, :runner_price_mismatch}
    end
  end

  defp validate_price(_price_id, _platform), do: {:error, :no_runner_prices_configured}

  defp correct_price?(
         %{
           currency: "usd",
           billing_scheme: "tiered",
           tiers_mode: "graduated",
           recurring: %{interval: "month", interval_count: 1, usage_type: "metered"},
           tiers: [free, paid]
         },
         platform
       ) do
    expected_rate = Decimal.div(Prepaid.on_demand_cost_for_milliseconds(platform, 6_000_000).amount, 6_000_000)
    rate = Decimal.new(Map.get(paid, :unit_amount_decimal) || to_string(Map.get(paid, :unit_amount, 0)))

    free.up_to == Allowance.free_monthly_minutes(platform) * 60_000 and zero?(free, :unit_amount) and
      zero?(free, :flat_amount) and zero?(paid, :flat_amount) and is_nil(paid.up_to) and
      Decimal.compare(Decimal.abs(Decimal.sub(rate, expected_rate)), Decimal.new("0.000000000001")) != :gt
  end

  defp correct_price?(_price, _platform), do: false

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

  defp validate(params) when is_map(params) do
    with true <- Enum.sort(Map.keys(params)) == Enum.sort(@fields),
         true <- is_integer(params["paid_cents"]) and params["paid_cents"] > 0,
         multiplier when is_binary(multiplier) and byte_size(multiplier) <= 20 <- params["credit_multiplier"],
         {multiplier, ""} <- Decimal.parse(multiplier),
         {:ok, _} <- Prepaid.quote_pool(params["paid_cents"], multiplier),
         platforms when is_list(platforms) and platforms != [] <- params["platforms"],
         true <- Enum.all?(platforms, &Map.has_key?(@platforms, &1)) and Enum.uniq(platforms) == platforms,
         true <- is_binary(params["starts_on"]) and byte_size(params["starts_on"]) == 10,
         true <- is_binary(params["expires_on"]) and byte_size(params["expires_on"]) == 10,
         {:ok, _} <- Date.from_iso8601(params["starts_on"]),
         {:ok, _} <- Date.from_iso8601(params["expires_on"]),
         "in_" <> invoice when byte_size(invoice) > 0 and byte_size(invoice) < 255 <- params["invoice_id"],
         true <- text?(params["expected_revision"], 64) and byte_size(params["expected_revision"]) == 64,
         true <- text?(params["reason"], 1000),
         {:ok, _} <- Ecto.UUID.cast(params["change_id"]),
         %{"id" => actor_id, "email" => email} = actor when map_size(actor) == 2 <- params["actor"],
         {:ok, _} <- Ecto.UUID.cast(actor_id),
         true <- text?(email, 320),
         true <- params["interface"] == "mcp" do
      :ok
    else
      _ -> {:error, :invalid_request}
    end
  end

  defp validate(_), do: {:error, :invalid_request}

  # `confirm_air_limits` is optional and only means anything to a cancel.
  defp validate_trial(params) when is_map(params) do
    with true <- Enum.sort(Map.keys(params) -- ["confirm_air_limits"]) == Enum.sort(@trial_fields),
         true <- params["operation"] in ~w(start cancel),
         true <-
           not Map.has_key?(params, "confirm_air_limits") or
             (params["operation"] == "cancel" and is_boolean(params["confirm_air_limits"])),
         true <- text?(params["expected_revision"], 64) and byte_size(params["expected_revision"]) == 64,
         true <- text?(params["reason"], 1000),
         {:ok, _} <- Ecto.UUID.cast(params["change_id"]),
         %{"id" => actor_id, "email" => email} = actor when map_size(actor) == 2 <- params["actor"],
         {:ok, _} <- Ecto.UUID.cast(actor_id),
         true <- text?(email, 320),
         true <- params["interface"] == "mcp" do
      :ok
    else
      _ -> {:error, :invalid_request}
    end
  end

  defp validate_trial(_), do: {:error, :invalid_request}
  defp text?(value, max), do: is_binary(value) and byte_size(value) <= max and String.trim(value) != ""
  defp expiry(params), do: Date.from_iso8601!(params["expires_on"])
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
