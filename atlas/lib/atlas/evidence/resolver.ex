defmodule Atlas.Evidence.Resolver do
  @moduledoc false

  alias Atlas.Accounts.Event
  alias Atlas.Accounts.Outcome
  alias Atlas.Accounts.OutcomeReview
  alias Atlas.Accounts.Term
  alias Atlas.Audit.Activity
  alias Atlas.Briefs.BriefItem
  alias Atlas.Documents.Document
  alias Atlas.Finance.Invoice
  alias Atlas.Finance.Transaction
  alias Atlas.Outreach.MessageAttempt
  alias Atlas.Product.Trace
  alias Atlas.Repo

  def resolve("account_event", id), do: resolve_record(Event, id, "internal", & &1.occurred_at)
  def resolve("account_term", id), do: resolve_record(Term, id, "internal", &term_time/1)
  def resolve("finance_invoice", id), do: resolve_record(Invoice, id, "restricted", &invoice_time/1)

  def resolve("finance_transaction", id), do: resolve_record(Transaction, id, "restricted", &Transaction.occurred_at/1)

  def resolve("account_outcome", id), do: resolve_record(Outcome, id, "internal", & &1.inserted_at)

  def resolve("account_outcome_review", id), do: resolve_record(OutcomeReview, id, "internal", & &1.reviewed_at)

  def resolve("outreach_message_attempt", id),
    do: resolve_record(MessageAttempt, id, "internal", &(&1.outcome_at || &1.sent_at || &1.inserted_at))

  def resolve("product_trace", id) do
    case Repo.get(Trace, id) do
      nil -> {:error, :evidence_record_not_found}
      trace -> {:ok, %{record: trace, sensitivity: trace.sensitivity, occurred_at: trace.occurred_at}}
    end
  end

  def resolve("document", id), do: resolve_record(Document, id, "restricted", & &1.inserted_at)
  def resolve("audit_activity", id), do: resolve_record(Activity, id, "internal", & &1.occurred_at)

  def resolve("brief_item", id) do
    case Repo.get(BriefItem, id) do
      nil -> {:error, :evidence_record_not_found}
      item -> {:ok, %{record: item, sensitivity: item.sensitivity, occurred_at: item.resolved_at || item.inserted_at}}
    end
  end

  def resolve(_record_type, _id), do: {:error, :unsupported_evidence_record}

  defp resolve_record(module, id, sensitivity, occurred_at) do
    case Repo.get(module, id) do
      nil -> {:error, :evidence_record_not_found}
      record -> {:ok, %{record: record, sensitivity: sensitivity, occurred_at: occurred_at.(record)}}
    end
  end

  defp invoice_time(invoice) do
    invoice.extracted_at || date_to_datetime(invoice.invoice_date) || invoice.inserted_at
  end

  defp term_time(term), do: date_to_datetime(term.start_date) || term.inserted_at

  defp date_to_datetime(%Date{} = date), do: DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
  defp date_to_datetime(_date), do: nil
end
