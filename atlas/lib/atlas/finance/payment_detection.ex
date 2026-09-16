defmodule Atlas.Finance.PaymentDetection do
  @moduledoc """
  Reviews a new incoming transaction and immediately celebrates confident
  customer payment matches without storing the classification.
  """

  alias Atlas.Accounts
  alias Atlas.Audit
  alias Atlas.Finance.Agents.PaymentDetectionAgent
  alias Atlas.Finance.PaymentCelebrationNotifier
  alias Atlas.Finance.Transaction

  require Logger

  def review_and_notify(%Transaction{direction: "credit", affects_runway: true} = transaction) do
    case PaymentDetectionAgent.run(transaction) do
      {:ok, %{status: "matched"} = detection} ->
        notify_match(transaction, detection)

      {:ok, %{status: status}} when status in ["not_payment", "unmatched"] ->
        {:ok, status}

      {:error, reason} ->
        Logger.warning("Payment detection failed for transaction #{transaction.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def review_and_notify(%Transaction{}), do: {:ok, "not_eligible"}

  defp notify_match(transaction, detection) do
    case Accounts.get_account(detection.account_id) do
      nil ->
        Logger.warning(
          "Payment detection matched transaction #{transaction.id} to missing account #{detection.account_id}"
        )

        {:error, :payment_account_not_found}

      account ->
        celebration = Map.take(detection, [:headline, :body])

        case PaymentCelebrationNotifier.maybe_post(transaction, account, celebration) do
          {:ok, slack} ->
            audit_notification(transaction, account, detection, slack)
            {:ok, "notified"}

          {:error, reason} = error ->
            Logger.warning("Payment celebration failed for transaction #{transaction.id}: #{inspect(reason)}")
            error
        end
    end
  end

  defp audit_notification(transaction, account, detection, slack) do
    Audit.record(
      "finance.customer_payment.celebrated",
      %{
        target_type: "account",
        target_id: account.id,
        target_label: account.name,
        metadata: %{
          "path" => "/commercial/sales/accounts/#{account.id}",
          "finance_transaction_id" => transaction.id,
          "provider" => transaction.provider,
          "amount_value" => Decimal.to_string(transaction.amount_value, :normal),
          "amount_currency" => transaction.amount_currency,
          "match_confidence" => decimal_to_string(detection.confidence),
          "match_reason" => detection.reason,
          "slack_channel_id" => slack.channel_id,
          "slack_ts" => slack.ts
        }
      },
      interface: "worker"
    )
  end

  defp decimal_to_string(nil), do: nil
  defp decimal_to_string(decimal), do: Decimal.to_string(decimal, :normal)
end
