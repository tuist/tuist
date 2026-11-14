defmodule TuistWeb.Webhooks.BillingController do
  @behaviour Stripe.WebhookHandler

  use TuistWeb, :controller

  alias Tuist.Accounts
  alias Tuist.Billing

  @impl true
  def handle_event(%Stripe.Event{type: "customer.updated"} = event) do
    customer = event.data.object

    case Accounts.get_account_from_customer_id(customer.id) do
      # A customer's email can be removed, but accounts.billing_email is NOT NULL.
      {:ok, account} when is_binary(customer.email) ->
        {:ok, _} = Accounts.update_account(account, %{billing_email: customer.email})
        :ok

      {:ok, _account} ->
        :ok

      {:error, :not_found} ->
        :ok
    end
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

  @impl true
  def handle_event(%Stripe.Event{type: "invoice.payment_failed"} = event) do
    Billing.on_invoice_payment_failed(event.data.object)
  end

  # Return HTTP 200 for unhandled events
  @impl true
  def handle_event(_event) do
    :ok
  end
end
