defmodule Tuist.Billing.Workers.PaymentFailedNotificationWorker do
  @moduledoc """
  Delivers one admin's failed-payment email, so a failed delivery retries
  without resending it to the admins who already got theirs.
  """
  use Oban.Worker, queue: :default, max_attempts: 5, unique: [keys: [:invoice_id, :user_id], period: :infinity]

  alias Tuist.Accounts
  alias Tuist.Accounts.User
  alias Tuist.Accounts.UserNotifier

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "invoice_id" => invoice_id,
          "account_id" => account_id,
          "user_id" => user_id,
          "plan_active_until" => plan_active_until
        }
      }) do
    with {:ok, account} <- Accounts.get_account_by_id(account_id),
         %User{} = user <- Accounts.get_user_by_id(user_id),
         true <- Accounts.owns_account_or_is_admin_to_account_organization?(user, account),
         true <- invoice_open?(invoice_id) do
      {:ok, plan_active_until, _offset} = DateTime.from_iso8601(plan_active_until)

      case UserNotifier.deliver_payment_failed_notification(user, account, plan_active_until) do
        {:ok, _email} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      _ -> :ok
    end
  end

  # A retry that succeeded before this ran leaves nothing to ask for.
  defp invoice_open?(invoice_id) do
    match?({:ok, %{status: "open"}}, Stripe.Invoice.retrieve(invoice_id))
  end
end
