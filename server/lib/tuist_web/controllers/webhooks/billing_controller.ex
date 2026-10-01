defmodule TuistWeb.Webhooks.BillingController do
  @behaviour Stripe.WebhookHandler

  use TuistWeb, :controller

  alias Tuist.Accounts
  alias Tuist.Billing
  alias Tuist.Billing.Workers.CreateRunnerPrepaidGrantWorker

  @impl true
  def handle_event(%Stripe.Event{} = event) do
    context = %{
      stripe_event_id: event.id,
      stripe_event_type: event.type,
      stripe_customer_id: customer_id(event.data.object)
    }

    Logger.metadata(Map.to_list(context))

    if Tuist.Environment.error_tracking_enabled?() do
      Sentry.Context.set_extra_context(context)
    end

    handle(event)
  end

  defp customer_id(%Stripe.Customer{id: id}), do: id
  defp customer_id(%{customer: customer_id}) when is_binary(customer_id), do: customer_id
  defp customer_id(_object), do: nil

  defp handle(%Stripe.Event{type: "customer.updated"} = event) do
    customer = event.data.object

    case Accounts.get_account_from_customer_id(customer.id) do
      # A customer's email can be removed, but accounts.billing_email is NOT NULL.
      {:ok, account} when is_binary(customer.email) ->
        {:ok, _} = Accounts.update_account(account, %{billing_email: customer.email})
        :ok

      {:ok, _account} ->
        :ok

      {:error, :not_found} ->
        Billing.on_unlinked_customer(customer)
    end
  end

  defp handle(%Stripe.Event{type: "customer.subscription.created"} = event) do
    Billing.on_subscription_change(event.data.object)

    :ok
  end

  defp handle(%Stripe.Event{type: "customer.subscription.updated"} = event) do
    Billing.on_subscription_change(event.data.object)

    :ok
  end

  defp handle(%Stripe.Event{type: "customer.subscription.deleted"} = event) do
    Billing.on_subscription_change(event.data.object)

    :ok
  end

  defp handle(%Stripe.Event{type: "customer.subscription.resumed"} = event) do
    Billing.on_subscription_change(event.data.object)

    :ok
  end

  defp handle(%Stripe.Event{type: "customer.subscription.paused"} = event) do
    Billing.on_subscription_change(event.data.object)

    :ok
  end

  defp handle(%Stripe.Event{type: "invoice.payment_failed"} = event) do
    Billing.on_invoice_payment_failed(event.data.object)
  end

  # Enqueued for every finalized and every paid invoice rather than only
  # for ones that look prepaid here. The webhook payload carries at most
  # the first handful of an invoice's lines, so a prepaid line sitting
  # further down a busy month's bill would be read as "not prepaid" and
  # the credit lost. The worker pages the lines endpoint and decides on
  # the full picture; an ordinary invoice costs it one cheap no-op.
  #
  # Finalization grants a renewal's standing prepaid minutes. Stripe
  # finalizes a subscription invoice about an hour after the period
  # opens however late it is paid, and a grant is effective only from
  # when it is created. Payment is the backstop when finalization was
  # never delivered. The worker skips lines already granted, so both
  # events grant an invoice once.
  #
  # Let a failed insert raise: any credit on the invoice is owed, so a
  # 500 here buys another delivery from Stripe rather than dropping the
  # grant on the floor.
  defp handle(%Stripe.Event{type: type} = event) when type in ["invoice.finalized", "invoice.paid"] do
    {:ok, _job} =
      %{invoice_id: event.data.object.id}
      |> CreateRunnerPrepaidGrantWorker.new()
      |> Oban.insert()

    :ok
  end

  # Return HTTP 200 for unhandled events
  defp handle(_event), do: :ok
end
