defmodule Atlas.Links do
  @moduledoc """
  Resolves only exact or explicitly verified links between domain records and accounts.

  Finance vendor invoices and bank transactions intentionally never resolve to
  customer accounts. Those associations were removed because they represented
  vendor costs, not customer activity.
  """

  alias Atlas.Accounts.Contact
  alias Atlas.Accounts.Event
  alias Atlas.Accounts.Invoice, as: AccountInvoice
  alias Atlas.Accounts.Outcome
  alias Atlas.Accounts.OutcomeReview
  alias Atlas.Accounts.Term
  alias Atlas.Documents.Document
  alias Atlas.Outreach.MessageAttempt
  alias Atlas.Outreach.Recommendation
  alias Atlas.Repo
  alias Atlas.Slack.Channel

  def resolve_account(record_type, record_id)

  def resolve_account("account_event", id), do: exact(Event, id, & &1.account_id, "account_event.account_id")
  def resolve_account("account_term", id), do: exact(Term, id, & &1.account_id, "account_term.account_id")
  def resolve_account("account_outcome", id), do: exact(Outcome, id, & &1.account_id, "account_outcome.account_id")
  def resolve_account("account_contact", id), do: exact(Contact, id, & &1.account_id, "account_contact.account_id")

  def resolve_account("account_invoice", id),
    do: exact(AccountInvoice, id, & &1.account_id, "account_invoice.account_id")

  def resolve_account("document", id), do: exact(Document, id, & &1.account_id, "document.account_id")
  def resolve_account("slack_channel", id), do: exact(Channel, id, & &1.account_id, "slack_channel.account_id")

  def resolve_account("outreach_message_attempt", id),
    do: exact(MessageAttempt, id, & &1.account_id, "outreach_message_attempt.account_id")

  def resolve_account("outreach_recommendation", id),
    do: exact(Recommendation, id, & &1.account_id, "outreach_recommendation.account_id")

  def resolve_account("account_outcome_review", id) do
    with %OutcomeReview{} = review <- Repo.get(OutcomeReview, id),
         %Outcome{} = outcome <- Repo.get(Outcome, review.outcome_id) do
      account_result(outcome.account_id, "account_outcome_review.outcome.account_id")
    else
      _missing -> :no_link
    end
  end

  def resolve_account(record_type, _id) when record_type in ["finance_invoice", "finance_transaction"], do: :no_link

  def resolve_account(_record_type, _id), do: :no_link

  def verified_account(account, basis) when is_binary(basis) and basis != "" do
    {:verified, account, basis}
  end

  defp exact(module, id, account_id, basis) do
    case Repo.get(module, id) do
      nil -> :no_link
      record -> account_result(account_id.(record), basis)
    end
  end

  defp account_result(nil, _basis), do: :no_link

  defp account_result(account_id, basis) do
    case Atlas.Accounts.get_account(account_id) do
      nil -> :no_link
      account -> {:exact, account, basis}
    end
  end
end
