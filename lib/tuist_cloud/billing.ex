defmodule TuistCloud.Billing do
  @moduledoc """
  A module for operations related to billing.
  """

  alias TuistCloud.Environment
  alias TuistCloud.Accounts
  alias TuistCloud.Accounts.Account
  alias TuistCloud.Repo

  def create_customer(%{name: name, email: email}) do
    if enabled?() do
      {:ok, customer} = Stripe.Customer.create(%{name: name, email: email})
      customer.id
    else
      nil
    end
  end

  def create_session(customer) do
    {:ok, session} = Stripe.BillingPortal.Session.create(%{customer: customer})
    session
  end

  def update_remote_cache_hit_meter({customer_id, count}) do
    path = Stripe.OpenApi.Path.replace_path_params("/v1/billing/meter_events", [], [])

    identifier =
      "#{customer_id}-#{TuistCloud.Time.utc_now() |> Timex.format!("{YYYY}.{0M}.{D}")}"

    {:ok, _} =
      Stripe.Request.new_request([])
      |> Stripe.Request.put_endpoint(path)
      |> Stripe.Request.put_params(%{
        event_name: "remote_cache_hit",
        identifier: identifier,
        payload: %{
          value: count,
          stripe_customer_id: customer_id
        }
      })
      |> Stripe.Request.put_method(:post)
      |> Stripe.Request.make_request()
  end

  def on_subscription_change(subscription) do
    account = Accounts.get_account_from_customer_id(subscription[:customer])
    active = subscription[:status] in ["active", "trialing"]
    subscription_prices = subscription[:items][:data] |> Enum.map(& &1[:price][:id])
    available_prices = TuistCloud.Environment.stripe_prices()

    plan =
      if active do
        plan =
          available_prices
          |> Enum.filter(fn {_, plan_prices} ->
            usage = plan_prices[:usage]
            flat = plan_prices[:flat]

            # The subscription must:
            #   - Include all the usage-based prices
            #   - Include at least one flat-based price (monthly or yearly)
            Enum.all?(usage, &Enum.member?(subscription_prices, &1)) and
              Enum.any?(flat, &Enum.member?(subscription_prices, &1))
          end)
          |> Enum.map(&elem(&1, 0))
          |> List.first()

        if plan == nil, do: :none, else: plan
      else
        :none
      end

    {:ok, _} = account |> Account.update_changeset(%{plan: plan}) |> Repo.update()
  end

  def enabled? do
    Environment.stripe_configured?()
  end
end
