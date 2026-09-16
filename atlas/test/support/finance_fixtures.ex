defmodule Atlas.FinanceFixtures do
  @moduledoc false

  alias Atlas.Finance.Account
  alias Atlas.Finance.Category
  alias Atlas.Finance.Invoice
  alias Atlas.Finance.InvoiceLineItem
  alias Atlas.Finance.Source
  alias Atlas.Finance.Transaction
  alias Atlas.Repo

  def insert_finance_source!(attrs \\ %{}) do
    defaults = %{
      provider: "qonto",
      name: "Finance Source",
      metadata: %{}
    }

    attrs =
      defaults
      |> Map.merge(attrs)
      |> Map.put(:config_key, unique_config_key(attrs))

    %Source{}
    |> Source.changeset(attrs)
    |> Repo.insert!()
    |> Repo.preload(:atlas_account)
  end

  # `finance_sources.config_key` is unique across the table, so two concurrent
  # tests inserting the same literal key block on each other's uncommitted index
  # entry, and two inserting the same pair of keys in opposite orders deadlock.
  # Callers keep passing readable keys like "qonto-main"; this keeps the key
  # recognizable while making it belong to exactly one test.
  defp unique_config_key(attrs) do
    prefix = Map.get(attrs, :config_key, "finance-source")

    "#{prefix}:#{System.unique_integer([:positive])}"
  end

  def insert_finance_account!(source, attrs \\ %{}) do
    defaults = %{
      finance_source_id: source.id,
      provider: source.provider,
      external_id: "finance-account:#{System.unique_integer([:positive])}",
      name: "Operating Account",
      account_type: "checking",
      currency: "EUR",
      main: true,
      status: "active",
      balance_value: Decimal.new("1000.00"),
      balance_currency: "EUR",
      available_balance_value: Decimal.new("900.00"),
      available_balance_currency: "EUR",
      metadata: %{}
    }

    %Account{}
    |> Account.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
    |> Repo.preload(source: :atlas_account)
  end

  def insert_finance_category!(attrs \\ %{}) do
    defaults = %{
      name: "Software",
      description: "Recurring software subscriptions",
      direction: "debit",
      metadata: %{}
    }

    attrs = defaults |> Map.merge(attrs) |> put_unique_slug()

    %Category{}
    |> Category.changeset(attrs)
    |> Repo.insert!()
  end

  # `finance_categories.slug` is unique across the table and `Category.changeset/2`
  # derives it from the name, so the handful of broad names these tests reuse
  # ("Software", "Cloud Infrastructure", "Payroll") collide across the modules
  # that now run concurrently. The name stays exactly as the caller wrote it,
  # since that is what gets rendered and asserted on; only the slug is scoped to
  # one test. Read it back off the returned record when a test filters by it.
  defp put_unique_slug(attrs) do
    Map.put_new_lazy(attrs, :slug, fn ->
      "#{Category.slugify(attrs.name)}-#{System.unique_integer([:positive])}"
    end)
  end

  def insert_finance_transaction!(account, attrs \\ %{}) do
    defaults = %{
      finance_account_id: account.id,
      provider: account.provider,
      external_id: "finance-transaction:#{System.unique_integer([:positive])}",
      status: "completed",
      direction: "debit",
      kind: "expense",
      counterparty_name: "Vendor",
      description: "Expense",
      amount_value: Decimal.new("100.00"),
      amount_currency: account.currency || "EUR",
      booked_at: ~U[2026-05-01 10:00:00Z],
      settled_at: ~U[2026-05-01 10:00:00Z],
      provider_updated_at: ~U[2026-05-01 10:00:00Z],
      metadata: %{},
      raw: %{}
    }

    %Transaction{}
    |> Transaction.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  def insert_finance_invoice!(attrs \\ %{}) do
    {document_id, attrs} = Map.pop(attrs, :document_id)
    {finance_transaction_id, attrs} = Map.pop(attrs, :finance_transaction_id)

    defaults = %{
      vendor_name: "Vendor",
      invoice_number: "INV-#{System.unique_integer([:positive])}",
      invoice_date: ~D[2026-05-01],
      status: "extracted",
      total_amount_value: Decimal.new("100.00"),
      total_amount_currency: "EUR",
      metadata: %{}
    }

    %Invoice{}
    |> Invoice.changeset(Map.merge(defaults, attrs))
    |> maybe_put_change(:document_id, document_id)
    |> maybe_put_change(:finance_transaction_id, finance_transaction_id)
    |> Repo.insert!()
  end

  def insert_finance_invoice_line_item!(invoice, attrs \\ %{}) do
    {_finance_invoice_id, attrs} = Map.pop(attrs, :finance_invoice_id)
    {finance_category_id, attrs} = Map.pop(attrs, :finance_category_id)

    defaults = %{
      description: "Line item",
      amount_value: Decimal.new("100.00"),
      amount_currency: invoice.total_amount_currency || "EUR",
      metadata: %{}
    }

    %InvoiceLineItem{finance_invoice_id: invoice.id}
    |> InvoiceLineItem.changeset(Map.merge(defaults, attrs))
    |> maybe_put_change(:finance_category_id, finance_category_id)
    |> Repo.insert!()
  end

  defp maybe_put_change(changeset, _key, nil), do: changeset
  defp maybe_put_change(changeset, key, value), do: Ecto.Changeset.put_change(changeset, key, value)
end
