defmodule Atlas.Finance do
  @moduledoc """
  Finance context for normalized treasury data ingested from external providers.
  """

  alias Atlas.Finance.Categorization
  alias Atlas.Finance.Config
  alias Atlas.Finance.ExpenseHistory
  alias Atlas.Finance.ExpenseReconciliation
  alias Atlas.Finance.Invoices
  alias Atlas.Finance.Overview
  alias Atlas.Finance.QontoInvoiceBackfill
  alias Atlas.Finance.Query
  alias Atlas.Finance.Runway
  alias Atlas.Finance.Sync

  defdelegate configured_sources(), to: Config
  defdelegate configured_source_keys(), to: Config
  defdelegate list_sources(opts \\ []), to: Query
  defdelegate list_accounts(opts \\ []), to: Query
  defdelegate list_categories(opts \\ []), to: Query
  defdelegate list_transactions(opts \\ []), to: Query
  defdelegate list_transactions_page(opts \\ []), to: Query
  defdelegate expense_reconciliation(opts), to: ExpenseReconciliation, as: :build
  defdelegate expense_history(opts \\ []), to: ExpenseHistory, as: :build
  defdelegate list_invoices(opts \\ []), to: Invoices
  defdelegate get_finance_invoice(id), to: Invoices, as: :get_invoice
  defdelegate get_finance_invoice_by_document(document), to: Invoices, as: :get_invoice_by_document
  defdelegate finance_invoice_for_transaction?(transaction), to: Invoices, as: :invoice_for_transaction?
  defdelegate upsert_extracted_invoice(document, attrs, line_items, opts \\ []), to: Invoices
  defdelegate mark_invoice_extraction_failed(document, reason, opts \\ []), to: Invoices
  defdelegate finance_cost_breakdown(opts \\ []), to: Invoices, as: :cost_breakdown
  defdelegate vendor_cost_analytics(opts \\ []), to: Invoices, as: :vendor_analytics
  defdelegate backfill_qonto_invoices(opts \\ []), to: QontoInvoiceBackfill, as: :run
  defdelegate overview(opts \\ []), to: Overview, as: :build
  defdelegate runway_window(opts \\ []), to: Runway, as: :window
  defdelegate cash_analytics(window), to: Runway
  defdelegate burn_rate_analytics(window), to: Runway
  defdelegate runway_analytics(window), to: Runway
  defdelegate net_flow_analytics(window), to: Runway
  defdelegate cash_flow_analytics(window), to: Runway
  defdelegate sync_source(source_key, opts \\ []), to: Sync, as: :run_source
  defdelegate categorize_transactions(opts \\ []), to: Categorization, as: :run
end
