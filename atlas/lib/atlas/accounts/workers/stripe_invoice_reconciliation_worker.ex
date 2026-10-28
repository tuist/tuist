defmodule Atlas.Accounts.Workers.StripeInvoiceReconciliationWorker do
  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    tags: ["accounts", "stripe", "invoices"]

  alias Atlas.Accounts

  @impl Oban.Worker
  def perform(%Oban.Job{} = job), do: perform(job, [])

  def perform(%Oban.Job{args: %{"account_id" => account_id}}, opts) do
    reconcile = Keyword.get(opts, :reconcile, &Accounts.reconcile_stripe_invoices/1)

    case reconcile.(account_id) do
      {:ok, _result} -> :ok
      :disabled -> {:cancel, :stripe_invoice_reconciliation_disabled}
      {:error, :not_found} -> {:cancel, :account_not_found}
      {:error, reason} -> {:error, reason}
    end
  end
end
