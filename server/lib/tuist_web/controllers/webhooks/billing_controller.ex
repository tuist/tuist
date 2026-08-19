defmodule TuistWeb.Webhooks.BillingController do
  @behaviour Stripe.WebhookHandler

  use TuistWeb, :controller

  alias Tuist.Accounts
  alias Tuist.Billing
  alias Tuist.Billing.Workers.CreateRunnerPrepaidGrantWorker

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

  # Enqueued for every paid invoice rather than only for ones that look
  # prepaid here. The webhook payload carries at most the first handful
  # of an invoice's lines, so a prepaid line sitting further down a
  # busy month's bill would be read as "not prepaid" and the credit
  # lost. The worker pages the lines endpoint and decides on the full
  # picture; an ordinary invoice costs it one cheap no-op.
  #
  # Let a failed insert raise: the invoice is paid and any credit on it
  # is owed, so a 500 here buys another delivery from Stripe rather
  # than dropping the grant on the floor.
  @impl true
  def handle_event(%Stripe.Event{type: "invoice.paid"} = event) do
    {:ok, _job} =
      %{invoice_id: event.data.object.id}
      |> CreateRunnerPrepaidGrantWorker.new()
      |> Oban.insert()

    :ok
  end

  # Return HTTP 200 for unhandled events
  @impl true
  def handle_event(_event) do
    :ok
  end
end
