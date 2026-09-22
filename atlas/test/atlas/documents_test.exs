defmodule Atlas.DocumentsTest do
  use Atlas.DataCase, async: true
  use Mimic
  use Oban.Testing, repo: Atlas.Repo

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Workers.ExtractDocumentServiceLevels
  alias Atlas.Documents
  alias Atlas.Documents.Correspondent
  alias Atlas.Documents.Document
  alias Atlas.Documents.DocumentPage
  alias Atlas.Documents.DocumentType
  alias Atlas.Documents.Tag
  alias Atlas.Documents.Workers.ProcessDocument
  alias Atlas.Repo
  alias Atlas.TestSupport.Documents.Classifier
  alias Atlas.TestSupport.Documents.FailingClassifier
  alias Atlas.TestSupport.Documents.InvoiceClassifier
  alias Atlas.TestSupport.Documents.NoopInvoiceExtractor
  alias Atlas.TestSupport.Documents.SignedOrderFormClassifier
  alias Atlas.Vector

  @tag :tmp_dir
  test "creates a document, stores the object, and processes page embeddings", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "service-agreement.txt")
    File.write!(path, "Service agreement\n\nThe counterparty is Acme.")

    assert {:ok, %Document{} = document} =
             Documents.create_from_path(
               path,
               %{
                 "original_filename" => "service-agreement.txt",
                 "content_type" => "text/plain",
                 "source" => "paperless"
               },
               enqueue?: false
             )

    assert document.status == "uploaded"
    assert document.storage_bucket == "test-documents"

    assert {:ok, %Document{} = processed} = Documents.process_document(document.id, classifier: Classifier)
    assert processed.status == "ready"
    assert processed.archive_serial_number == 1

    processed = Documents.get_document(processed.id)
    assert processed.document_type.name == "contract"
    assert processed.correspondent.name == "Acme"
    assert processed.document_date == ~D[2026-01-15]
    assert Enum.sort(Enum.map(processed.tags, & &1.name)) == ["legal", "renewal"]

    pages = Repo.all(DocumentPage)
    assert length(pages) == 1
    assert hd(pages).embedding_model == "test-embedding"
  end

  @tag :tmp_dir
  test "associates a processed document with a matching account", %{tmp_dir: tmp_dir} do
    account = insert_account!(%{name: "Acme", primary_domain: "acme.example", legal_name: "Acme Inc."})
    path = Path.join(tmp_dir, "acme-security-review.txt")
    File.write!(path, "Security review for Acme Inc. Primary domain: acme.example.")

    {:ok, document} =
      Documents.create_from_path(
        path,
        %{
          "original_filename" => "acme-security-review.txt",
          "content_type" => "text/plain",
          "source" => "paperless"
        },
        enqueue?: false
      )

    assert {:ok, %Document{} = processed} = Documents.process_document(document.id, classifier: Classifier)
    assert processed.account_id == account.id
    assert_enqueued(worker: ExtractDocumentServiceLevels, args: %{"document_id" => document.id})

    assert [%Document{id: document_id}] = Documents.list_account_documents(account)
    assert document_id == document.id
  end

  @tag :tmp_dir
  test "does not associate a processed invoice with a matching account", %{tmp_dir: tmp_dir} do
    _account = insert_account!(%{name: "Cloudflare", primary_domain: "cloudflare.com", legal_name: "Cloudflare, Inc."})
    path = Path.join(tmp_dir, "cloudflare-invoice.txt")
    File.write!(path, "Invoice from Cloudflare, Inc. for cloudflare.com services.")

    {:ok, document} =
      Documents.create_from_path(
        path,
        %{
          "original_filename" => "cloudflare-invoice.txt",
          "content_type" => "text/plain",
          "source" => "paperless"
        },
        enqueue?: false
      )

    assert {:ok, %Document{} = processed} =
             Documents.process_document(document.id,
               classifier: InvoiceClassifier,
               invoice_extractor: NoopInvoiceExtractor
             )

    assert processed.account_id == nil
    refute_enqueued(worker: ExtractDocumentServiceLevels, args: %{"document_id" => document.id})
  end

  test "creates a document directly from bytes and assigns a programmatic account" do
    account = insert_account!(%{name: "Acme", primary_domain: "acme.example"})
    body = "%PDF-1.4\n%%EOF\n"

    assert {:ok, %Document{} = document} =
             Documents.create_from_binary(
               body,
               %{
                 "original_filename" => "signed-agreement.pdf",
                 "content_type" => "application/pdf",
                 "source" => "email",
                 "account_id" => account.id,
                 "attributes" => %{"email" => %{"message_id" => "message-123"}}
               },
               enqueue?: false
             )

    assert document.source == "email"
    assert document.account_id == account.id
    assert document.byte_size == byte_size(body)
    assert document.attributes == %{"email" => %{"message_id" => "message-123"}}
  end

  @tag :tmp_dir
  test "syncs an account's commercial fields when a signed order form is processed", %{tmp_dir: tmp_dir} do
    account =
      insert_account!(%{
        name: "Acme Corp",
        primary_domain: "notion.so",
        segment: :prospect,
        deal_stage: nil,
        currency: nil,
        current_value: nil,
        next_renewal_date: nil
      })

    path = Path.join(tmp_dir, "notion-order-form.txt")
    File.write!(path, "ORDER FORM\n\nAcme Corp annual subscription.\nSigned by Ji Pei on 2026-06-10.")

    {:ok, document} =
      Documents.create_from_path(
        path,
        %{
          "original_filename" => "notion-order-form.txt",
          "content_type" => "text/plain",
          "source" => "upload",
          "account_id" => account.id
        },
        enqueue?: false
      )

    assert {:ok, %Document{}} = Documents.process_document(document.id, classifier: SignedOrderFormClassifier)

    refreshed = Repo.get!(Account, account.id)
    assert refreshed.segment == :customer
    assert refreshed.deal_stage == "closed_won"
    assert refreshed.currency == "USD"
    assert Decimal.equal?(refreshed.current_value, Decimal.new("16200"))
    assert refreshed.next_renewal_date == ~D[2027-05-01]
    assert refreshed.poc_end_date == ~D[2027-05-01]
  end

  @tag :tmp_dir
  test "does not overwrite a curated deal stage when a signed order form is reprocessed", %{tmp_dir: tmp_dir} do
    account =
      insert_account!(%{
        name: "Acme Corp",
        primary_domain: "notion.so",
        segment: :prospect,
        deal_stage: "negotiation",
        poc_end_date: ~D[2026-08-15]
      })

    path = Path.join(tmp_dir, "notion-order-form-2.txt")
    File.write!(path, "ORDER FORM\n\nAcme Corp annual subscription.\nSigned by Ji Pei on 2026-06-10.")

    {:ok, document} =
      Documents.create_from_path(
        path,
        %{
          "original_filename" => "notion-order-form-2.txt",
          "content_type" => "text/plain",
          "source" => "upload",
          "account_id" => account.id
        },
        enqueue?: false
      )

    assert {:ok, _document} = Documents.process_document(document.id, classifier: SignedOrderFormClassifier)

    refreshed = Repo.get!(Account, account.id)
    assert refreshed.segment == :customer
    assert refreshed.deal_stage == "negotiation"
    assert refreshed.poc_end_date == ~D[2026-08-15]
  end

  @tag :tmp_dir
  test "keeps a preassigned account when processing cannot infer one from the document", %{tmp_dir: tmp_dir} do
    account = insert_account!(%{name: "Acme", primary_domain: "acme.example"})
    path = Path.join(tmp_dir, "generic-agreement.txt")
    File.write!(path, "Generic agreement with no account identifier.")

    {:ok, document} =
      Documents.create_from_path(
        path,
        %{
          "original_filename" => "generic-agreement.txt",
          "content_type" => "text/plain",
          "source" => "email",
          "account_id" => account.id
        },
        enqueue?: false
      )

    assert {:ok, processed} = Documents.process_document(document.id, classifier: Classifier)
    assert processed.account_id == account.id
  end

  # Scanned-image PDFs (e.g. Qonto receipts uploaded from a phone camera)
  # yield no extractable text, so processing ends up with zero pages. The
  # deterministic classifier can still resolve the invoice from the title and
  # Qonto attributes, so the document must finalize as `ready` rather than
  # sitting in `failed` with no document type.
  @tag :tmp_dir
  test "classifies a Qonto invoice attachment when text extraction yielded no pages", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "IMG_20260907_092016.txt")
    File.write!(path, "")

    {:ok, document} =
      Documents.create_from_path(
        path,
        %{
          "title" => "Qonto invoice EL PETIT VEGA D'EN PEP",
          "original_filename" => "IMG_20260907_092016.txt",
          "content_type" => "text/plain",
          "source" => "qonto",
          "document_date" => "2026-09-07",
          "attributes" => %{
            "document_type" => "invoice",
            "qonto_source_key" => "qonto",
            "qonto_transaction_id" => "01a075db-1ae0-7e19-9a23-fc0f9119b595",
            "qonto_attachment_id" => "01a07abd-3d32-7c34-abf1-6a5ca927ff9d"
          }
        },
        enqueue?: false
      )

    assert {:ok, %Document{} = processed} =
             Documents.process_document(document.id,
               classifier: FailingClassifier,
               invoice_extractor: NoopInvoiceExtractor
             )

    assert processed.status == "ready"

    reloaded = Documents.get_document(processed.id)
    assert reloaded.document_type.name == "invoice"
    assert reloaded.correspondent.name == "EL PETIT VEGA D'EN PEP"
    assert reloaded.document_date == ~D[2026-09-07]
    assert Enum.sort(Enum.map(reloaded.tags, & &1.name)) == ["finance", "invoice"]
    assert reloaded.attributes["classification"]["source"] == "deterministic"
    assert Repo.all(DocumentPage) == []
  end

  test "backfills document account associations from existing pages" do
    account = insert_account!(%{name: "Acme", primary_domain: "acme.example"})
    document = insert_document!("Acme Security Packet", %{summary: "Evidence requested for acme.example"})

    %DocumentPage{}
    |> DocumentPage.changeset(%{
      document_id: document.id,
      page_number: 1,
      content: "Acme procurement asks for SOC2 evidence for acme.example."
    })
    |> Repo.insert!()

    assert %{matched: 1, unmatched: 0, failed: 0} = Documents.backfill_document_accounts()
    assert Repo.get!(Document, document.id).account_id == account.id
  end

  test "does not backfill account from generic body word variants" do
    account = insert_account!(%{name: "Booking", primary_domain: "booking.com"})

    document =
      insert_document!("Overview of Fees and Services", %{
        summary: "Fee schedule including excess bookings and special services."
      })

    %DocumentPage{}
    |> DocumentPage.changeset(%{
      document_id: document.id,
      page_number: 1,
      content: "SW Digital Tax service packages include business management analysis and excess bookings."
    })
    |> Repo.insert!()

    assert %{matched: 0, unmatched: 1, failed: 0} = Documents.backfill_document_accounts()
    assert Repo.get!(Document, document.id).account_id != account.id
    assert is_nil(Repo.get!(Document, document.id).account_id)
  end

  test "does not backfill account from internal classification attribute tokens" do
    account = insert_account!(%{name: "Agents", primary_domain: "agents.example"})

    document =
      insert_document!("Quarterly Report", %{
        summary: "Revenue figures for the last quarter.",
        attributes: %{
          "classification" => %{
            "status" => "classified",
            "source" => "agent",
            "classifier" => "Atlas.Documents.Agents.DocumentClassifierAgent"
          }
        }
      })

    _page = insert_page!(document, "Revenue figures for the last quarter.")

    assert %{matched: 0, unmatched: 1, failed: 0} = Documents.backfill_document_accounts()

    reloaded = Repo.get!(Document, document.id)
    assert reloaded.account_id != account.id
    assert is_nil(reloaded.account_id)
  end

  test "lists ready documents that still need classifier metadata" do
    fallback =
      insert_document!("Fallback Invoice", %{
        summary: nil,
        document_date: nil,
        attributes: %{"classification" => %{"status" => "fallback"}}
      })

    _fallback_page = insert_page!(fallback, "Invoice text")

    classified =
      insert_document!("Classified Contract", %{
        summary: "Already classified.",
        document_date: ~D[2026-01-15],
        attributes: %{"classification" => %{"status" => "classified"}}
      })
      |> put_correspondent!(Documents.upsert_correspondent("Acme"))
      |> put_document_type!(Documents.upsert_document_type("contract"))

    _classified_page = insert_page!(classified, "Contract text")

    assert Documents.list_document_classification_candidate_ids() == [fallback.id]
  end

  test "classifies metadata for an already processed fallback document" do
    document =
      insert_document!("Fallback Agreement", %{
        summary: nil,
        document_date: nil,
        attributes: %{"classification" => %{"status" => "fallback"}}
      })

    _page = insert_page!(document, "Service agreement\n\nThe counterparty is Acme.")

    assert {:ok, %Document{} = updated} =
             Documents.classify_document_metadata(document.id, classifier: Classifier)

    assert updated.summary == "A searchable imported document."
    assert updated.attributes["counterparty"] == "Acme"
    assert updated.attributes["classification"]["status"] == "classified"
    assert updated.attributes["classification"]["source"] == "agent"

    reloaded = Documents.get_document(document.id)
    assert reloaded.document_type.name == "contract"
    assert reloaded.correspondent.name == "Acme"
    assert reloaded.document_date == ~D[2026-01-15]
    assert Enum.sort(Enum.map(reloaded.tags, & &1.name)) == ["legal", "renewal"]
    assert Documents.list_document_classification_candidate_ids() == []
  end

  test "classifies obvious finance receipts without the agent classifier" do
    document =
      insert_document!("Qonto invoice TOGETHER COMPUTER, INC", %{
        original_filename: "qonto-invoice-together-computer-2026-07-07.txt",
        summary: nil,
        document_date: nil,
        attributes: %{"classification" => %{"status" => "fallback"}}
      })

    _page =
      insert_page!(
        document,
        """
        Invoice number INV-123
        Date paid July 7, 2026
        Amount paid $100.00
        """
      )

    assert {:ok, %Document{} = updated} =
             Documents.classify_document_metadata(document.id, classifier: FailingClassifier)

    assert updated.summary == "Invoice from TOGETHER COMPUTER, INC for 100.00 USD."
    assert updated.document_date == ~D[2026-07-07]
    assert updated.attributes["amount"] == "100.00"
    assert updated.attributes["currency"] == "USD"
    assert updated.attributes["classification"]["status"] == "classified"
    assert updated.attributes["classification"]["source"] == "deterministic"

    reloaded = Documents.get_document(document.id)
    assert reloaded.document_type.name == "invoice"
    assert reloaded.correspondent.name == "TOGETHER COMPUTER, INC"
    assert Enum.sort(Enum.map(reloaded.tags, & &1.name)) == ["finance", "invoice"]
  end

  test "keeps a document recoverable and preserves metadata when backfill classification fails" do
    document =
      insert_document!("Fallback Agreement", %{
        summary: "Existing summary.",
        document_date: ~D[2026-01-15],
        attributes: %{"classification" => %{"status" => "fallback"}}
      })

    _page = insert_page!(document, "Service agreement text.")

    assert {:error, {:session_exit, :timeout}} =
             Documents.classify_document_metadata(document.id, classifier: FailingClassifier)

    reloaded = Documents.get_document(document.id)

    # A failed classification must not stamp the document "classified" (which
    # would exclude it forever) nor wipe metadata it already had.
    assert reloaded.summary == "Existing summary."
    assert reloaded.document_date == ~D[2026-01-15]
    assert reloaded.attributes["classification"]["status"] == "failed"
    assert Documents.list_document_classification_candidate_ids() == [document.id]
  end

  test "reconciles stale account associations from generic body word variants" do
    account = insert_account!(%{name: "Booking", primary_domain: "booking.com"})

    document =
      insert_document!("Overview of Fees and Services", %{
        summary: "Fee schedule including excess bookings and special services."
      })
      |> Ecto.Changeset.change(account_id: account.id)
      |> Repo.update!()

    %DocumentPage{}
    |> DocumentPage.changeset(%{
      document_id: document.id,
      page_number: 1,
      content: "SW Digital Tax service packages include business management analysis and excess bookings."
    })
    |> Repo.insert!()

    assert %{updated: 1, unchanged: 0, failed: 0} = Documents.reconcile_document_accounts()
    assert is_nil(Repo.get!(Document, document.id).account_id)
  end

  test "reconciles stale account associations from invoice documents" do
    account = insert_account!(%{name: "Cloudflare", primary_domain: "cloudflare.com"})
    invoice_type = Documents.upsert_document_type("Invoice")

    document =
      insert_document!("Cloudflare Invoice", %{
        summary: "Invoice from Cloudflare for cloudflare.com services."
      })
      |> Ecto.Changeset.change(account_id: account.id, document_type_id: invoice_type.id)
      |> Repo.update!()

    assert %{updated: 1, unchanged: 0, failed: 0} = Documents.reconcile_document_accounts()
    assert is_nil(Repo.get!(Document, document.id).account_id)
  end

  test "lists documents by text query" do
    insert_document!("Security Policy", %{summary: "Incident response and access control"})
    insert_document!("Vendor Agreement", %{summary: "Commercial terms"})

    assert [%Document{title: "Security Policy"}] = Documents.list_documents(query: "incident")
  end

  describe "search_document_matches/2" do
    setup do
      stub(Vector, :configured?, fn -> false end)
      :ok
    end

    test "matches document metadata and joined metadata fields" do
      document_type = Documents.upsert_document_type("Compliance Packet")
      correspondent = Documents.upsert_correspondent("Globex Legal")
      account = insert_account!(%{name: "Aperture Procurement", primary_domain: "aperture.example"})
      tag = Documents.upsert_tag("Renewal Window")

      title_document = insert_document!("Alpha Board Approval", %{})
      filename_document = insert_document!("Filename Routed Notice", %{original_filename: "source-filename-marker.txt"})
      summary_document = insert_document!("Summary Routed Notice", %{summary: "Contains summary-only-token details."})
      type_document = insert_document!("Type Routed Notice", %{}) |> put_document_type!(document_type)
      correspondent_document = insert_document!("Correspondent Routed Notice", %{}) |> put_correspondent!(correspondent)
      account_document = insert_document!("Account Routed Notice", %{}) |> put_account!(account)
      tag_document = insert_document!("Tag Routed Notice", %{}) |> put_tags!([tag])

      cases = [
        {"alpha board", title_document},
        {"source-filename-marker", filename_document},
        {"summary-only-token", summary_document},
        {"compliance packet", type_document},
        {"globex legal", correspondent_document},
        {"aperture procurement", account_document},
        {"renewal window", tag_document}
      ]

      for {query, expected_document} <- cases do
        assert {:ok, [%{document: document, match: %{sources: [:metadata]}}]} =
                 Documents.search_document_matches(query, limit: 10)

        assert document.id == expected_document.id
      end
    end

    test "returns an empty list when metadata and page text do not match" do
      insert_document!("Security Policy", %{summary: "Incident response and access control"})
      insert_page!("Quarterly financial report and audit findings.")

      assert {:ok, []} = Documents.search_document_matches("nonexistent terminology xyzzy")
    end

    test "applies excluded tag filters to page text matches" do
      renewal_tag = Documents.upsert_tag("Renewal")
      finance_tag = Documents.upsert_tag("Finance")

      excluded_document =
        insert_document!("Renewal Packet", %{})
        |> put_tags!([renewal_tag, finance_tag])

      matching_document =
        insert_document!("Finance Packet", %{})
        |> put_tags!([finance_tag])

      insert_page!(excluded_document, "Signed board consent appointing a new managing director.")
      insert_page!(matching_document, "Signed board consent appointing a new managing director.")

      assert {:ok, rows} = Documents.search_document_matches("managing director", limit: 10, exclude_tag: "Renewal")
      assert Enum.map(rows, & &1.document.id) == [matching_document.id]
    end

    test "sorts inserted_at matches chronologically rather than by struct term order" do
      # Jan 31 vs Mar 1: day-of-month (31 vs 1) is the opposite order to the actual
      # dates, so a term-order sort of the NaiveDateTime structs would rank them wrong.
      older = insert_document!("Ledger Reconciliation Alpha", %{}) |> put_inserted_at!(~N[2026-01-31 10:00:00])
      newer = insert_document!("Ledger Reconciliation Beta", %{}) |> put_inserted_at!(~N[2026-03-01 10:00:00])

      assert {:ok, desc_rows} =
               Documents.search_document_matches("ledger reconciliation",
                 limit: 10,
                 sort_by: "inserted_at",
                 sort_order: "desc"
               )

      assert Enum.map(desc_rows, & &1.document.id) == [newer.id, older.id]

      assert {:ok, asc_rows} =
               Documents.search_document_matches("ledger reconciliation",
                 limit: 10,
                 sort_by: "inserted_at",
                 sort_order: "asc"
               )

      assert Enum.map(asc_rows, & &1.document.id) == [older.id, newer.id]
    end

    test "applies date sort before truncating to the page limit" do
      # Metadata candidates are relevance-ranked newest-first, so requesting the oldest
      # match with limit 1 fails if truncation happens before the sort.
      older = insert_document!("Quarterly Vendor Statement One", %{}) |> put_inserted_at!(~N[2026-01-10 00:00:00])
      _newer = insert_document!("Quarterly Vendor Statement Two", %{}) |> put_inserted_at!(~N[2026-05-10 00:00:00])

      assert {:ok, [%{document: document}]} =
               Documents.search_document_matches("quarterly vendor statement",
                 limit: 1,
                 sort_by: "inserted_at",
                 sort_order: "asc"
               )

      assert document.id == older.id
    end
  end

  @tag :tmp_dir
  test "indexes each page in the OpenData vector service during processing", %{tmp_dir: tmp_dir} do
    test_pid = self()

    stub(Vector, :upsert_vectors, fn records ->
      send(test_pid, {:upsert_vectors, records})
      {:ok, %{"vectorsUpserted" => length(records)}}
    end)

    path = Path.join(tmp_dir, "service-agreement.txt")
    File.write!(path, "Service agreement\n\nThe counterparty is Acme.")

    {:ok, document} =
      Documents.create_from_path(
        path,
        %{"original_filename" => "service-agreement.txt", "content_type" => "text/plain", "source" => "paperless"},
        enqueue?: false
      )

    assert {:ok, _processed} = Documents.process_document(document.id, classifier: Classifier)

    assert_received {:upsert_vectors, [record]}
    assert String.starts_with?(record.id, "document_page:")
    assert record.attributes["source_type"] == "document_page"
    assert record.attributes["document_id"] == document.id
    assert is_list(record.vector)
  end

  @tag :tmp_dir
  test "semantic_search returns vector hits hydrated from postgres", %{tmp_dir: tmp_dir} do
    stub(Vector, :upsert_vectors, fn _records -> {:ok, %{}} end)

    path = Path.join(tmp_dir, "service-agreement.txt")
    File.write!(path, "Service agreement\n\nThe counterparty is Acme.")

    {:ok, document} =
      Documents.create_from_path(
        path,
        %{"original_filename" => "service-agreement.txt", "content_type" => "text/plain", "source" => "paperless"},
        enqueue?: false
      )

    {:ok, _processed} = Documents.process_document(document.id, classifier: Classifier)
    page = Repo.one(DocumentPage)

    stub(Vector, :configured?, fn -> true end)

    stub(Vector, :search, fn _vector, _opts ->
      {:ok, %{"results" => [%{"vector" => %{"id" => "document_page:#{page.id}"}, "score" => 0.91}]}}
    end)

    assert {:ok, [hit]} = Documents.semantic_search("agreement")
    assert hit.id == page.id
    assert hit.document_id == document.id
    assert hit.page_number == page.page_number
    # Score is now a fused reciprocal-rank score, not the raw vector score.
    assert is_float(hit.score) and hit.score > 0
    assert hit.title == "service agreement"
  end

  describe "list_documents_page/1" do
    test "paginates with Flop offsets and reports total and cursors" do
      for i <- 1..3, do: insert_document!("Doc #{i}", %{})

      {page1, meta1} = Documents.list_documents_page(limit: 2, offset: 0)
      assert length(page1) == 2
      assert meta1.total_count == 3
      assert meta1.has_next_page?
      refute meta1.has_previous_page?

      {page2, meta2} = Documents.list_documents_page(limit: 2, offset: 2)
      assert length(page2) == 1
      assert meta2.has_previous_page?
      refute meta2.has_next_page?

      ids1 = Enum.map(page1, & &1.id)
      refute Enum.any?(page2, &(&1.id in ids1))
    end

    test "excludes documents by tag without matching other tags on the same document" do
      renewal_tag = Documents.upsert_tag("Renewal")
      finance_tag = Documents.upsert_tag("Finance")

      excluded_document =
        insert_document!("Renewal Finance Packet", %{})
        |> put_tags!([renewal_tag, finance_tag])

      matching_document =
        insert_document!("Finance Packet", %{})
        |> put_tags!([finance_tag])

      {documents, _meta} = Documents.list_documents_page(exclude_tag: "Renewal")
      document_ids = Enum.map(documents, & &1.id)

      assert matching_document.id in document_ids
      refute excluded_document.id in document_ids
    end
  end

  describe "semantic_search/2 hybrid retrieval" do
    test "uses short network timeouts for interactive vector search" do
      test_pid = self()

      stub(Vector, :configured?, fn -> true end)

      stub(Vector, :search, fn _vector, opts ->
        assert opts[:receive_timeout] == 1_000
        {:ok, %{"results" => []}}
      end)

      assert {:ok, []} =
               Documents.semantic_search("financial audit",
                 client: nil,
                 api_key: "secret",
                 req: embedding_req(test_pid)
               )

      assert_receive {:embedding_request, %Req.Request{} = request}
      assert request.options.receive_timeout == 1_000
    end

    test "returns full-text matches when vector search stalls" do
      stub(Vector, :configured?, fn -> true end)
      page = insert_page!("Quarterly financial report and audit findings.")

      # The embedding request never returns, so the vector task can never finish
      # and the timeout always elapses regardless of scheduling. Don't assert on
      # anything the vector task does here: it is shut down with :brutal_kill
      # once the deadline fires, so under load it may be killed before it runs
      # at all. The embedding request itself is covered by the test above.
      assert {:ok, [hit]} =
               Documents.semantic_search("financial audit",
                 client: nil,
                 api_key: "secret",
                 req: stalling_embedding_req(),
                 vector_timeout: 50
               )

      # Nothing is asserted about the embedding request here on purpose. The
      # search brutal-kills the vector task once `vector_timeout` elapses, so on
      # a loaded machine the task can be killed before it is ever scheduled and
      # the request is never issued at all. What matters is that the stall does
      # not stop full-text results from coming back; the request options are
      # covered by the test above, which lets the vector side complete.
      assert hit.id == page.id
      assert is_float(hit.score) and hit.score > 0
    end

    test "keeps explicit vector search timeouts" do
      test_pid = self()

      stub(Vector, :configured?, fn -> true end)

      stub(Vector, :search, fn _vector, opts ->
        assert opts[:receive_timeout] == 1_250
        {:ok, %{"results" => []}}
      end)

      assert {:ok, []} =
               Documents.semantic_search("financial audit",
                 client: nil,
                 api_key: "secret",
                 req: embedding_req(test_pid),
                 receive_timeout: 750,
                 vector_receive_timeout: 1_250
               )

      assert_receive {:embedding_request, %Req.Request{} = request}
      assert request.options.receive_timeout == 750
    end

    test "returns full-text matches when the vector service is unconfigured" do
      stub(Vector, :configured?, fn -> false end)
      page = insert_page!("Quarterly financial report and audit findings.")

      assert {:ok, [hit]} = Documents.semantic_search("financial audit")
      assert hit.id == page.id
      assert is_float(hit.score) and hit.score > 0
    end

    test "returns an empty list for a blank query" do
      assert {:ok, []} = Documents.semantic_search("   ")
    end

    test "returns an empty list when nothing matches" do
      stub(Vector, :configured?, fn -> false end)
      insert_page!("Unrelated content about gardening schedules.")

      assert {:ok, []} = Documents.semantic_search("nonexistent terminology xyzzy")
    end
  end

  describe "process_document/2 classifier fallback" do
    @tag :tmp_dir
    test "falls back to filename metadata when the classifier fails and fallback is enabled", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "invoice-2026.txt")
      File.write!(path, "Some extractable text.")

      {:ok, document} =
        Documents.create_from_path(
          path,
          %{"original_filename" => "invoice-2026.txt", "content_type" => "text/plain", "source" => "paperless"},
          enqueue?: false
        )

      assert {:ok, processed} =
               Documents.process_document(document.id, classifier: FailingClassifier, classify_fallback?: true)

      assert processed.status == "ready"
      # Fallback derives a type from the filename but no agent correspondent/summary.
      assert processed.correspondent_id == nil
      assert processed.summary == nil
      assert processed.attributes["classification"]["status"] == "fallback"
      assert processed.attributes["classification"]["source"] == "filename"
      assert processed.attributes["classification"]["last_error"] =~ "timeout"
      assert Repo.aggregate(DocumentPage, :count) == 1
    end

    @tag :tmp_dir
    test "fails for retry when the classifier fails and fallback is disabled", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "invoice-2026.txt")
      File.write!(path, "Some extractable text.")

      {:ok, document} =
        Documents.create_from_path(
          path,
          %{"original_filename" => "invoice-2026.txt", "content_type" => "text/plain", "source" => "paperless"},
          enqueue?: false
        )

      assert {:error, {:session_exit, :timeout}} =
               Documents.process_document(document.id, classifier: FailingClassifier)

      assert Repo.get(Document, document.id).status == "failed"
    end
  end

  describe "resolve_correspondent/1, resolve_document_type/1, resolve_tag/1" do
    test "reuses an existing entry by case-insensitive name" do
      existing = Documents.upsert_correspondent("Acme")

      assert Documents.resolve_correspondent("acme").id == existing.id
      assert Repo.aggregate(Correspondent, :count) == 1
    end

    test "reuses a fuzzily matching entry instead of creating a near-duplicate" do
      existing = Documents.upsert_correspondent("Acme Inc.")

      assert Documents.resolve_correspondent("Acme Inc").id == existing.id
      assert Repo.aggregate(Correspondent, :count) == 1
    end

    test "creates a new entry when nothing similar exists" do
      _acme = Documents.upsert_correspondent("Acme")

      globex = Documents.resolve_correspondent("Globex")

      assert globex.name == "Globex"
      assert Repo.aggregate(Correspondent, :count) == 2
    end

    test "returns nil for a blank or non-binary name" do
      assert Documents.resolve_correspondent("   ") == nil
      assert Documents.resolve_correspondent(nil) == nil
    end

    test "resolve_document_type reuses across case differences" do
      type = Documents.resolve_document_type("Contract")

      assert Documents.resolve_document_type("contract").id == type.id
      assert Repo.aggregate(DocumentType, :count) == 1
    end

    test "resolve_tag assigns a palette color and reuses by name" do
      tag = Documents.resolve_tag("finance")

      assert tag.color in Tag.colors()
      assert Documents.resolve_tag("finance").id == tag.id
    end
  end

  # Backfill helper for reprocessing documents that landed in `failed` before
  # the extractor tolerated zero-page PDFs. Only `failed` rows are safe to
  # re-enqueue unconditionally: they have no in-flight Oban job by definition.
  describe "reenqueue_failed_documents/0" do
    test "enqueues ProcessDocument for every failed row and skips the rest" do
      failed_one = insert_document!("Failed 1", %{status: "failed", last_error: ":empty_document"})
      failed_two = insert_document!("Failed 2", %{status: "failed", last_error: ":empty_document"})
      _ready = insert_document!("Ready", %{status: "ready"})
      _uploaded = insert_document!("Uploaded", %{status: "uploaded"})
      _processing = insert_document!("Processing", %{status: "processing"})

      assert %{enqueued: 2} = Documents.reenqueue_failed_documents()

      assert_enqueued(worker: ProcessDocument, args: %{"document_id" => failed_one.id})
      assert_enqueued(worker: ProcessDocument, args: %{"document_id" => failed_two.id})
      assert Enum.count(all_enqueued(worker: ProcessDocument)) == 2
    end

    test "returns zero and enqueues nothing when no rows are failed" do
      _ready = insert_document!("Ready", %{status: "ready"})

      assert %{enqueued: 0} = Documents.reenqueue_failed_documents()
      assert all_enqueued(worker: ProcessDocument) == []
    end
  end

  defp insert_page!(content) do
    document = insert_document!("Doc #{System.unique_integer([:positive])}", %{})

    insert_page!(document, content)
  end

  defp insert_page!(%Document{} = document, content) do
    %DocumentPage{}
    |> DocumentPage.changeset(%{document_id: document.id, page_number: 1, content: content})
    |> Repo.insert!()
  end

  defp embedding_req(test_pid) do
    fn %Req.Request{} = request ->
      send(test_pid, {:embedding_request, request})

      {:ok, %Req.Response{status: 200, body: %{"data" => [%{"embedding" => [0.0]}]}}}
    end
  end

  # Stalls forever: nothing ever sends :unblock_embedding, so the caller blocks
  # until it is killed. This makes "the vector search did not come back in time"
  # deterministic instead of a race against a wall-clock deadline.
  defp stalling_embedding_req do
    fn %Req.Request{} ->
      receive do
        :unblock_embedding -> {:ok, %Req.Response{status: 200, body: %{"data" => [%{"embedding" => [0.0]}]}}}
      end
    end
  end

  defp insert_account!(attrs) do
    defaults = %{
      account_key: "account:#{System.unique_integer([:positive])}",
      name: "Account",
      segment: :lead
    }

    %Account{}
    |> Account.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp put_document_type!(%Document{} = document, %DocumentType{} = document_type) do
    document
    |> Ecto.Changeset.change(document_type_id: document_type.id)
    |> Repo.update!()
  end

  defp put_correspondent!(%Document{} = document, %Correspondent{} = correspondent) do
    document
    |> Ecto.Changeset.change(correspondent_id: correspondent.id)
    |> Repo.update!()
  end

  defp put_account!(%Document{} = document, %Account{} = account) do
    document
    |> Ecto.Changeset.change(account_id: account.id)
    |> Repo.update!()
  end

  defp put_inserted_at!(%Document{} = document, inserted_at) do
    document
    |> Ecto.Changeset.change(inserted_at: inserted_at)
    |> Repo.update!()
  end

  defp put_tags!(%Document{} = document, tags) when is_list(tags) do
    document
    |> Repo.preload(:tags)
    |> Document.tags_changeset(tags)
    |> Repo.update!()
  end

  defp insert_document!(title, attrs) do
    defaults = %{
      title: title,
      original_filename: "#{title}.txt",
      content_type: "text/plain",
      byte_size: 10,
      checksum_sha256: "#{System.unique_integer([:positive])}",
      storage_bucket: "test-documents",
      storage_key: "documents/#{System.unique_integer([:positive])}.txt",
      status: "ready",
      source: "upload"
    }

    %Document{}
    |> Document.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end
end
