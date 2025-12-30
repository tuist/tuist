defmodule TuistWeb.Webhooks.BillingController do
  @behaviour Stripe.WebhookHandler

  use TuistWeb, :controller

  alias Tuist.Accounts
  alias Tuist.Billing

  @impl true
  def handle_event(%Stripe.Event{type: "customer.updated"} = event) do
    customer = event.data.object
    {:ok, account} = Accounts.get_account_from_customer_id(customer.id)
    {:ok, _} = Accounts.update_account(account, %{billing_email: customer.email})

    :ok
  end

  @impl true
  def handle_event(%Stripe.Event{type: "customer.subscription.created"} = event) do
    Billing.on_subscription_change(event.data.object)

    :ok
  end

  @impl true
  def handle_event(%Stripe.Event{type: "customer.subscription.updated"} = event) do
    Billing.on_subscription_change(event.data.object)

    :ok
  end

  @impl true
  def handle_event(%Stripe.Event{type: "customer.subscription.deleted"} = event) do
    Billing.on_subscription_change(event.data.object)

    :ok
  end

  @impl true
  def handle_event(%Stripe.Event{type: "customer.subscription.resumed"} = event) do
    Billing.on_subscription_change(event.data.object)

    :ok
  end

  @impl true
  def handle_event(%Stripe.Event{type: "customer.subscription.paused"} = event) do
    Billing.on_subscription_change(event.data.object)

    :ok
  end

  # Return HTTP 200 for unhandled events
  @impl true
  def handle_event(_event) do
    :ok
  end
end
