defmodule Atlas.Finance.QontoInvoiceBackfillTest do
  use Atlas.DataCase, async: true
  use Mimic

  import Atlas.FinanceFixtures

  alias Atlas.Accounts.Account, as: AtlasAccount
  alias Atlas.Documents
  alias Atlas.Documents.Document
  alias Atlas.Finance.Account
  alias Atlas.Finance.Providers.Qonto
  alias Atlas.Finance.QontoInvoiceBackfill
  alias Atlas.Finance.Transaction
  alias Atlas.Repo

  test "imports Qonto transaction attachments as invoice documents once" do
    atlas_account = insert_atlas_account!(%{name: "Qonto", primary_domain: "qonto.com"})
    source = insert_finance_source!(%{provider: "qonto", config_key: "qonto-main", atlas_account_id: atlas_account.id})
    account = insert_finance_account!(source)

    transaction =
      insert_finance_transaction!(account, %{
        external_id: "txn-qonto-1",
        provider: "qonto",
        direction: "debit",
        counterparty_name: "AWS",
        amount_value: Decimal.new("120.00")
      })

    finance_config = [
      sources: [
        %{key: source.config_key, provider: :qonto, name: "Qonto Main"}
      ]
    ]

    expect(Qonto, :list_transaction_attachments, fn source_config, "txn-qonto-1" ->
      assert source_config.key == source.config_key
      {:ok, [%{"id" => "att-1", "file_name" => "aws-invoice.pdf", "file_content_type" => "application/pdf"}]}
    end)

    expect(Qonto, :download_attachment, fn _source_config, %{"id" => "att-1"} = attachment ->
      {:ok,
       %{
         body: "%PDF invoice",
         filename: attachment["file_name"],
         content_type: attachment["file_content_type"],
         byte_size: 12,
         probative?: false,
         attachment: attachment
       }}
    end)

    assert {:ok, %{documents_imported: 1, attachments_seen: 1}} =
             QontoInvoiceBackfill.run(
               finance_config: finance_config,
               batch_size: 1,
               sync_historical_transactions?: false
             )

    assert Documents.imported_from_qonto_attachment?("att-1")
    assert %Document{account_id: nil} = Repo.get_by!(Document, source: "qonto")

    transaction = Repo.reload!(transaction)
    assert transaction.metadata["qonto_invoice_backfilled"]

    assert {:ok, %{transactions_seen: 0, documents_imported: 0, skipped: 0}} =
             QontoInvoiceBackfill.run(
               finance_config: finance_config,
               batch_size: 1,
               sync_historical_transactions?: false
             )

    refute Atlas.Finance.finance_invoice_for_transaction?(transaction)
  end

  test "drains all eligible Qonto transactions across batches" do
    source = insert_finance_source!(%{provider: "qonto", config_key: "qonto-main"})
    account = insert_finance_account!(source)

    insert_finance_transaction!(account, %{external_id: "txn-qonto-1", provider: "qonto", direction: "debit"})
    insert_finance_transaction!(account, %{external_id: "txn-qonto-2", provider: "qonto", direction: "debit"})

    finance_config = [sources: [%{key: source.config_key, provider: :qonto, name: "Qonto Main"}]]

    expect(Qonto, :list_transaction_attachments, 2, fn _source_config, transaction_id ->
      assert transaction_id in ["txn-qonto-1", "txn-qonto-2"]
      {:ok, []}
    end)

    assert {:ok, %{transactions_seen: 2, attachments_seen: 0, documents_imported: 0}} =
             QontoInvoiceBackfill.run(
               finance_config: finance_config,
               batch_size: 1,
               sync_historical_transactions?: false
             )
  end

  test "skips Qonto attachments whose file already exists" do
    source = insert_finance_source!(%{provider: "qonto", config_key: "qonto-main"})
    account = insert_finance_account!(source)
    body = "%PDF existing invoice"
    insert_document_with_body!(body, %{source: "upload", original_filename: "existing.pdf"})

    transaction =
      insert_finance_transaction!(account, %{
        external_id: "txn-qonto-duplicate-file",
        provider: "qonto",
        direction: "debit",
        counterparty_name: "AWS"
      })

    finance_config = [sources: [%{key: source.config_key, provider: :qonto, name: "Qonto Main"}]]

    expect(Qonto, :list_transaction_attachments, fn _source_config, "txn-qonto-duplicate-file" ->
      {:ok,
       [%{"id" => "att-duplicate-file", "file_name" => "aws-invoice.pdf", "file_content_type" => "application/pdf"}]}
    end)

    expect(Qonto, :download_attachment, fn _source_config, %{"id" => "att-duplicate-file"} = attachment ->
      {:ok,
       %{
         body: body,
         filename: attachment["file_name"],
         content_type: attachment["file_content_type"],
         byte_size: byte_size(body),
         probative?: false,
         attachment: attachment
       }}
    end)

    assert {:ok, %{transactions_seen: 1, attachments_seen: 1, documents_imported: 0, skipped: 1, errors: []}} =
             QontoInvoiceBackfill.run(
               finance_config: finance_config,
               batch_size: 1,
               sync_historical_transactions?: false
             )

    refute Documents.imported_from_qonto_attachment?("att-duplicate-file")

    transaction = Repo.reload!(transaction)
    assert transaction.metadata["qonto_invoice_backfilled"]
  end

  test "hydrates historical Qonto transactions before importing attachments" do
    now = ~U[2026-06-19 10:00:00Z]
    source = insert_finance_source!(%{provider: "qonto", config_key: "qonto-main"})

    finance_config = [
      sources: [
        %{key: source.config_key, provider: :qonto, name: "Qonto Main"}
      ]
    ]

    expect(Qonto, :list_accounts, fn source_config ->
      assert source_config.key == source.config_key

      {:ok,
       [
         %{
           external_id: "qonto-account-1",
           name: "Operating",
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
       ]}
    end)

    expect(Qonto, :list_transactions, fn _source_config, %Account{external_id: "qonto-account-1"}, opts ->
      assert Keyword.fetch!(opts, :synced_after) == nil
      assert Keyword.fetch!(opts, :now) == now

      {:ok,
       %{
         transactions: [
           %{
             external_id: "txn-historical-1",
             status: "completed",
             direction: "debit",
             kind: "expense",
             counterparty_name: "Hetzner Online GmbH",
             description: "Cloud hosting",
             reference: "HETZNER-2026-04",
             amount_value: Decimal.new("1057.34"),
             amount_currency: "EUR",
             booked_at: ~U[2026-04-27 08:00:00Z],
             settled_at: ~U[2026-04-27 08:00:00Z],
             provider_updated_at: ~U[2026-04-28 08:00:00Z],
             affects_cash_balance: true,
             affects_runway: true,
             metadata: %{"category" => "hosting"},
             raw: %{"id" => "txn-historical-1"}
           }
         ],
         next_cursor: now
       }}
    end)

    expect(Qonto, :list_transaction_attachments, fn _source_config, "txn-historical-1" ->
      {:ok, [%{"id" => "att-historical-1", "file_name" => "hetzner.pdf", "file_content_type" => "application/pdf"}]}
    end)

    expect(Qonto, :download_attachment, fn _source_config, %{"id" => "att-historical-1"} = attachment ->
      {:ok,
       %{
         body: "%PDF invoice",
         filename: attachment["file_name"],
         content_type: attachment["file_content_type"],
         byte_size: 12,
         probative?: false,
         attachment: attachment
       }}
    end)

    assert {:ok,
            %{
              accounts_seen: 1,
              transactions_synced: 1,
              transactions_seen: 1,
              attachments_seen: 1,
              documents_imported: 1
            }} =
             QontoInvoiceBackfill.run(finance_config: finance_config, batch_size: 1, now: now)

    account = Repo.get_by!(Account, finance_source_id: source.id, external_id: "qonto-account-1")
    assert account.transactions_synced_at == nil

    transaction = Repo.get_by!(Transaction, finance_account_id: account.id, external_id: "txn-historical-1")
    assert transaction.metadata["category"] == "hosting"
    assert transaction.metadata["qonto_invoice_backfilled"]

    assert Documents.imported_from_qonto_attachment?("att-historical-1")
    assert %Document{account_id: nil} = Repo.get_by!(Document, source: "qonto")
  end

  defp insert_atlas_account!(attrs) do
    defaults = %{
      account_key: "account:#{System.unique_integer([:positive])}",
      name: "Account",
      segment: :lead
    }

    %AtlasAccount{}
    |> AtlasAccount.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_document_with_body!(body, attrs) do
    checksum = :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)

    defaults = %{
      title: "Existing invoice",
      original_filename: "existing.pdf",
      content_type: "application/pdf",
      byte_size: byte_size(body),
      checksum_sha256: checksum,
      storage_bucket: "test-documents",
      storage_key: "documents/#{checksum}.pdf",
      source: "upload",
      status: "ready"
    }

    %Document{}
    |> Document.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end
end
