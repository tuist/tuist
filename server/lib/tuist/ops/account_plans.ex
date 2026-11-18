defmodule Tuist.Ops.AccountPlans do
  @moduledoc """
  Audited, revision-checked plan changes for Atlas, the counterpart of the
  ops account page's plan buttons: upgrade to Enterprise, start the open
  source plan, and cancel the live subscription at the end of its period.

  Like `Tuist.Ops.RunnerConcurrencyLimits`, a write names the revision it
  read, a reason and a change UUID, and the request, workload principal and
  before/after state are recorded with it. The change itself lands in Stripe
  through the same `Tuist.Billing` functions the ops page calls, so it is not
  rolled back with this transaction: a request that fails after Stripe
  accepted it records nothing here, and the subscription webhooks bring the
  local subscription rows (and so the revision) in line.
  """

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Billing
  alias Tuist.Billing.Subscription
  alias Tuist.Ops.AccountPlanChange
  alias Tuist.Repo

  @operations ~w(upgrade_to_enterprise start_open_source cancel_at_period_end)
  @fields ~w(operation billing_details expected_revision reason change_id actor interface)
  @address_fields ~w(line1 line2 city state postal_code country)
  @required_address_fields ~w(line1 city postal_code country)
  # The plans the ops page offers to cancel.
  @cancellable_plans [:pro, :enterprise, :open_source]
  @recent_subscriptions 10

  def get(account_id) do
    with {:ok, id} <- account_id(account_id),
         {:ok, account} <- fetch_account(id) do
      {:ok, snapshot(account)}
    end
  end

  def update(account_id, params, principal) do
    with {:ok, id} <- account_id(account_id),
         :ok <- validate_request(params) do
      Repo.transaction(
        fn ->
          # Serializes Atlas plan changes per account, so two requests cannot
          # both pass the revision check and each create a subscription.
          account =
            Repo.one(from(account in Account, where: account.id == ^id, lock: "FOR UPDATE")) ||
              Repo.rollback(:resource_not_found)

          case Repo.get_by(AccountPlanChange, change_id: params["change_id"]) do
            nil -> apply_change(account, params, principal)
            change -> replay(change, id, params)
          end
        end,
        # Stripe calls run inside the transaction.
        timeout: to_timeout(minute: 1)
      )
    end
  end

  # An identical retry returns the recorded result, even after later changes.
  defp replay(%AccountPlanChange{account_id: account_id, request: params, after: after_state}, account_id, params),
    do: after_state

  defp replay(_change, _account_id, _params), do: Repo.rollback(:change_id_conflict)

  defp apply_change(account, params, principal) do
    before_state = snapshot(account)
    if before_state.revision != params["expected_revision"], do: Repo.rollback(:stale_revision)

    # Inserted before Stripe is called: a concurrent request reusing the
    # change ID waits on the unique index and conflicts instead of changing
    # Stripe a second time.
    change =
      %{
        change_id: params["change_id"],
        account_id: account.id,
        request: params,
        principal: principal,
        before: json_map(before_state),
        after: %{}
      }
      |> AccountPlanChange.create_changeset()
      |> Repo.insert()
      |> case do
        {:ok, change} -> change
        {:error, _changeset} -> Repo.rollback(:change_id_conflict)
      end

    change_plan(params["operation"], account, params)

    after_state = account |> Repo.reload!() |> snapshot() |> json_map()
    change |> Ecto.Changeset.change(after: after_state) |> Repo.update!()
    after_state
  end

  defp change_plan("upgrade_to_enterprise", account, params) do
    if Billing.effective_plan(account) == :enterprise, do: Repo.rollback(:already_enterprise)

    billing_details = billing_params(params["billing_details"])

    # The ops page asks for these in a modal when Stripe lacks them; an
    # invoice-billed subscription cannot be created without them.
    if billing_details == %{} and not customer_billing_details?(account),
      do: Repo.rollback(:billing_details_required)

    {:ok, _subscription} = Billing.upgrade_to_enterprise(account, billing_details)
  end

  defp change_plan("start_open_source", account, _params) do
    case Billing.start_open_source_plan(account) do
      {:ok, _subscription} -> :ok
      {:error, :subscription_exists} -> Repo.rollback(:subscription_exists)
    end
  end

  defp change_plan("cancel_at_period_end", account, _params) do
    case Billing.get_current_active_subscription(account) do
      %Subscription{plan: plan, cancel_at_period_end: false} = subscription when plan in @cancellable_plans ->
        case Billing.cancel_subscription_at_period_end(subscription) do
          # Synced here as the webhook would, so the returned state shows it.
          {:ok, stripe_subscription} -> Billing.on_subscription_change(stripe_subscription)
          {:error, _reason} -> Repo.rollback(:stripe_request_failed)
        end

      _ ->
        Repo.rollback(:no_cancellable_subscription)
    end
  end

  defp customer_billing_details?(%Account{customer_id: nil}), do: false

  defp customer_billing_details?(%Account{customer_id: customer_id}) do
    case Stripe.Customer.retrieve(customer_id) do
      {:ok, customer} -> Billing.billing_details_complete?(customer)
      {:error, _reason} -> Repo.rollback(:stripe_request_failed)
    end
  end

  defp billing_params(nil), do: %{}

  defp billing_params(%{"name" => name, "email" => email, "address" => address}) do
    %{
      name: name,
      billing_email: email,
      address:
        Map.reject(
          %{
            line1: address["line1"],
            line2: address["line2"],
            city: address["city"],
            state: address["state"],
            postal_code: address["postal_code"],
            country: String.upcase(address["country"])
          },
          fn {_key, value} -> is_nil(value) end
        )
    }
  end

  defp snapshot(%Account{} = account) do
    live =
      Repo.all(
        from(subscription in Subscription,
          where: subscription.account_id == ^account.id,
          where: subscription.status in ^Billing.live_subscription_statuses(),
          order_by: subscription.id
        )
      )

    recent =
      Repo.all(
        from(subscription in Subscription,
          where: subscription.account_id == ^account.id,
          order_by: [desc: subscription.inserted_at, desc: subscription.id],
          limit: @recent_subscriptions
        )
      )

    last_change =
      Repo.one(from(change in AccountPlanChange, where: change.account_id == ^account.id, select: max(change.id)))

    # Webhooks touch `updated_at` on every subscription change, and ops page
    # changes arrive through them, so either invalidates the revision.
    revision =
      live
      |> Enum.map(
        &{&1.id, &1.subscription_id, Atom.to_string(&1.plan), &1.status, &1.cancel_at_period_end,
         NaiveDateTime.to_iso8601(&1.updated_at)}
      )
      |> then(&{&1, last_change})
      |> :erlang.term_to_binary()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    current = Billing.get_current_active_subscription(account)

    %{
      account_id: account.id,
      account_handle: account.name,
      stripe_customer_id: account.customer_id,
      effective_plan: Atom.to_string(Billing.effective_plan(account)),
      subscription: current && subscription_json(current),
      recent_subscriptions: Enum.map(recent, &subscription_json/1),
      payment_failed: Billing.payment_failed?(account),
      cache_access_blocked: Billing.cache_access_blocked?(account),
      revision: revision
    }
  end

  defp subscription_json(%Subscription{} = subscription) do
    %{
      subscription_id: subscription.subscription_id,
      plan: Atom.to_string(subscription.plan),
      status: subscription.status,
      cancel_at_period_end: subscription.cancel_at_period_end,
      current_period_start: subscription.current_period_start,
      current_period_end: subscription.current_period_end,
      trial_end: subscription.trial_end,
      created_at: utc(subscription.inserted_at),
      updated_at: utc(subscription.updated_at)
    }
  end

  defp utc(%NaiveDateTime{} = value), do: DateTime.from_naive!(value, "Etc/UTC")

  defp fetch_account(id) do
    case Repo.get(Account, id) do
      nil -> {:error, :resource_not_found}
      account -> {:ok, account}
    end
  end

  defp account_id(id) when is_integer(id) and id > 0 and id <= 9_223_372_036_854_775_807, do: {:ok, id}

  defp account_id(id) when is_binary(id) and byte_size(id) in 1..19 do
    case Integer.parse(id) do
      {id, ""} -> account_id(id)
      _ -> {:error, :invalid_target}
    end
  end

  defp account_id(_id), do: {:error, :invalid_target}

  defp validate_request(params) when is_map(params) do
    with true <- Enum.all?(Map.keys(params), &(&1 in @fields)),
         true <- params["operation"] in @operations,
         true <- valid_billing_details?(params["operation"], Map.fetch(params, "billing_details")),
         true <- params["interface"] in ~w(mcp worker api),
         true <- text?(params["reason"], 1000),
         true <- String.trim(params["reason"]) != "",
         true <- is_binary(params["expected_revision"]) and byte_size(params["expected_revision"]) == 64,
         {:ok, _} <- Ecto.UUID.cast(params["change_id"]),
         %{"id" => id, "email" => email} = actor when map_size(actor) == 2 <- params["actor"],
         {:ok, _} <- Ecto.UUID.cast(id),
         true <- text?(email, 320) do
      :ok
    else
      _ -> {:error, :invalid_request}
    end
  end

  defp validate_request(_), do: {:error, :invalid_request}

  defp valid_billing_details?(_operation, :error), do: true

  defp valid_billing_details?(
         "upgrade_to_enterprise",
         {:ok, %{"name" => name, "email" => email, "address" => address} = details}
       )
       when map_size(details) == 3 and is_map(address) do
    text?(name, 255) and text?(email, 320) and String.contains?(email, "@") and
      Enum.all?(Map.keys(address), &(&1 in @address_fields)) and
      Enum.all?(@required_address_fields, &Map.has_key?(address, &1)) and
      Enum.all?(Map.values(address), &text?(&1, 255)) and
      String.match?(address["country"], ~r/\A[A-Za-z]{2}\z/)
  end

  defp valid_billing_details?(_operation, _details), do: false

  defp text?(value, max), do: is_binary(value) and byte_size(value) in 1..max and String.trim(value) != ""

  defp json_map(value), do: value |> JSON.encode!() |> JSON.decode!()
end
