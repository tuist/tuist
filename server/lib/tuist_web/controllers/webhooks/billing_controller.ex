defmodule TuistWeb.Webhooks.BillingController do
  @behaviour Stripe.WebhookHandler

  use TuistWeb, :controller

  alias Tuist.Accounts
  alias Tuist.Billing
  alias Tuist.Billing.Workers.CreateRunnerPrepaidGrantWorker
  alias Tuist.Runners.Prepaid

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

  # Every subscription renewal fires this too, so the marker is checked
  # here rather than enqueueing a job per invoice that immediately
  # no-ops. An invoice whose marker is present but malformed still
  # enqueues, so the mistake surfaces as a failing job instead of being
  # read as "not prepaid".
  @impl true
  def handle_event(%Stripe.Event{type: "invoice.paid"} = event) do
    invoice = event.data.object

    # Let a failed insert raise: the invoice is paid and the grant is
    # owed, so a 500 here buys another delivery from Stripe rather than
    # dropping the credit on the floor.
    if Prepaid.prepaid_invoice?(invoice) do
      {:ok, _job} =
        %{invoice_id: invoice.id}
        |> CreateRunnerPrepaidGrantWorker.new()
        |> Oban.insert()
    end

    :ok
  end

  # Return HTTP 200 for unhandled events
  @impl true
  def handle_event(_event) do
    :ok
  end
end
