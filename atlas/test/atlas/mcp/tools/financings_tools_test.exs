defmodule Atlas.MCP.Tools.FinancingsToolsTest do
  use Atlas.MCP.ToolCase

  import Atlas.AssetsFixtures
  import Atlas.FinanceFixtures
  import Atlas.FinancingsFixtures

  alias Atlas.Documents.Document
  alias Atlas.Finance.Financings
  alias Atlas.MCP.Tools.AttachDocumentToFinancing
  alias Atlas.MCP.Tools.CreateFinancing
  alias Atlas.MCP.Tools.DeleteFinancing
  alias Atlas.MCP.Tools.DetachDocumentFromFinancing
  alias Atlas.MCP.Tools.EditFinancingMetadata
  alias Atlas.MCP.Tools.ExercisePurchaseOption
  alias Atlas.MCP.Tools.GetFinancing
  alias Atlas.MCP.Tools.ListFinancings
  alias Atlas.MCP.Tools.MarkFinancingPaidOff
  alias Atlas.MCP.Tools.ReturnFinancing
  alias Atlas.MCP.Tools.SetFinancingAccountingTreatment
  alias Atlas.MCP.Tools.SetFinancingLines
  alias Atlas.MCP.Tools.TerminateFinancing

  test "list_financings returns rows as executive" do
    _ = insert_financing!()
    _ = insert_financing!(%{type: "lease_with_purchase_option"})

    assert {:ok, %{financings: rows, count: count}} =
             execute_tool(ListFinancings, executive_mcp_conn(), %{})

    assert count == length(rows)
    assert count >= 2
  end

  test "list_financings denies non-executives" do
    non_exec = insert_user!()
    assert {:error, message} = ListFinancings.execute(mcp_conn(non_exec), %{})
    assert message =~ "executives"
  end

  test "list_financings searches by reference, provider, or supplier" do
    financing =
      insert_financing!(%{
        provider: "Targo #{System.unique_integer([:positive])}",
        supplier: "Apple",
        reference: "4333811"
      })

    assert {:ok, %{financings: [result], count: 1}} =
             execute_tool(ListFinancings, executive_mcp_conn(), %{"query" => "4333811"})

    assert result.id == financing.id
  end

  test "create_financing creates a loan" do
    args = %{
      "type" => "loan",
      "provider" => "Test Bank",
      "disbursement_or_commencement_on" => "2026-01-15",
      "currency" => "EUR",
      "term_months" => 36,
      "principal_amount" => "30000.00"
    }

    assert {:ok, payload} = execute_tool(CreateFinancing, executive_mcp_conn(), args)
    assert payload.type == "loan"
    assert payload.provider == "Test Bank"
  end

  test "attaches typed documents and exposes them on the financing" do
    financing = insert_financing!(%{provider: "Targo", supplier: "Apple"})
    document = insert_document!("Apple supplier contract")

    assert {:ok, attachment} =
             execute_tool(AttachDocumentToFinancing, executive_mcp_conn(), %{
               "financing_id" => financing.id,
               "document_id" => document.id,
               "kind" => "supplier_contract"
             })

    assert {:ok, payload} =
             execute_tool(GetFinancing, executive_mcp_conn(), %{"financing_id" => financing.id})

    assert payload.supplier == "Apple"
    assert [%{document_id: document_id, kind: "supplier_contract"}] = payload.documents
    assert document_id == document.id

    assert {:ok, %{deleted: true}} =
             execute_tool(DetachDocumentFromFinancing, executive_mcp_conn(), %{
               "link_id" => attachment.id
             })
  end

  test "exposes the hardware allocations on the financing" do
    financing = insert_financing!(%{provider: "Targo", supplier: "Apple"})
    asset = insert_asset!(%{name: "Mac mini"})
    {:ok, _lines} = Financings.set_lines(financing, [%{asset_id: asset.id, share_bps: 10_000}])

    assert {:ok, payload} =
             execute_tool(GetFinancing, executive_mcp_conn(), %{"financing_id" => financing.id})

    assert [%{asset_id: asset_id, share_basis_points: 10_000}] = payload.asset_allocations
    assert asset_id == asset.id
  end

  test "get_financing returns a serialized financing" do
    financing = insert_financing!()

    assert {:ok, payload} =
             execute_tool(GetFinancing, executive_mcp_conn(), %{"financing_id" => financing.id})

    assert payload.id == financing.id
  end

  test "set_financing_accounting_treatment records the change" do
    financing = insert_financing!()

    assert {:ok, payload} =
             execute_tool(SetFinancingAccountingTreatment, executive_mcp_conn(), %{
               "financing_id" => financing.id,
               "accounting_treatment" => "capitalized",
               "evidence" => "Accountant sign-off"
             })

    assert payload.accounting_treatment == "capitalized"
  end

  test "set_financing_lines atomically replaces the set" do
    financing = insert_financing!(%{type: "lease_with_purchase_option"})
    asset_a = insert_asset!()
    asset_b = insert_asset!()

    assert {:ok, %{line_count: 2}} =
             execute_tool(SetFinancingLines, executive_mcp_conn(), %{
               "financing_id" => financing.id,
               "lines" => [
                 %{"asset_id" => asset_a.id, "share_bps" => 5_000},
                 %{"asset_id" => asset_b.id, "share_bps" => 5_000}
               ]
             })
  end

  test "exercise_purchase_option flips ownership" do
    financing = insert_financing!(%{type: "lease_with_purchase_option"})
    asset = insert_asset!(%{ownership: "leased"})
    {:ok, _} = Financings.set_lines(financing, [%{asset_id: asset.id, share_bps: 10_000}])

    source = insert_finance_source!()
    account = insert_finance_account!(source)

    txn =
      insert_finance_transaction!(account, %{
        amount_value: financing.purchase_option_amount,
        amount_currency: financing.currency,
        direction: "debit"
      })

    assert {:ok, payload} =
             execute_tool(ExercisePurchaseOption, executive_mcp_conn(), %{
               "financing_id" => financing.id,
               "on" => "2029-02-01",
               "option_transaction_id" => txn.id
             })

    assert payload.status == "option_exercised"
  end

  test "return_financing marks a lease returned" do
    financing = insert_financing!(%{type: "lease_with_purchase_option"})
    asset = insert_asset!(%{ownership: "leased"})
    {:ok, _} = Financings.set_lines(financing, [%{asset_id: asset.id, share_bps: 10_000}])

    assert {:ok, payload} =
             execute_tool(ReturnFinancing, executive_mcp_conn(), %{
               "financing_id" => financing.id,
               "on" => "2029-02-01"
             })

    assert payload.status == "returned"
  end

  test "edit_financing_metadata updates non-lifecycle fields" do
    financing = insert_financing!()

    assert {:ok, payload} =
             execute_tool(EditFinancingMetadata, executive_mcp_conn(), %{
               "financing_id" => financing.id,
               "provider" => "Updated Bank",
               "notes" => "revised"
             })

    assert payload.provider == "Updated Bank"
  end

  test "mark_financing_paid_off transitions status" do
    financing = insert_financing!()

    assert {:ok, payload} =
             execute_tool(MarkFinancingPaidOff, executive_mcp_conn(), %{
               "financing_id" => financing.id,
               "on" => "2029-01-15"
             })

    assert payload.status == "paid_off"
  end

  test "delete_financing removes an active arrangement with no payments" do
    financing = insert_financing!()

    assert {:ok, %{deleted: true, financing_id: id}} =
             execute_tool(DeleteFinancing, executive_mcp_conn(), %{"financing_id" => financing.id})

    assert id == financing.id
    assert Financings.get(financing.id) == nil
  end

  test "delete_financing refuses when the financing has payments" do
    financing = insert_financing!()

    source = insert_finance_source!()
    account = insert_finance_account!(source)

    txn =
      insert_finance_transaction!(account, %{
        amount_value: Decimal.new("100.00"),
        amount_currency: financing.currency,
        direction: "debit"
      })

    _ = insert_payment!(financing, txn)

    assert {:error, message} =
             execute_tool(DeleteFinancing, executive_mcp_conn(), %{"financing_id" => financing.id})

    assert message =~ "payments"
  end

  test "terminate_financing terminates a loan without touching assets" do
    financing = insert_financing!()
    asset = insert_asset!()
    {:ok, _} = Financings.set_lines(financing, [%{asset_id: asset.id, share_bps: 10_000}])

    assert {:ok, payload} =
             execute_tool(TerminateFinancing, executive_mcp_conn(), %{
               "financing_id" => financing.id,
               "on" => "2026-06-01",
               "reason" => "Early payoff"
             })

    assert payload.status == "terminated"
  end

  defp insert_document!(title) do
    unique = System.unique_integer([:positive])

    %Document{}
    |> Document.changeset(%{
      title: title,
      original_filename: "financing-#{unique}.pdf",
      content_type: "application/pdf",
      byte_size: 100,
      checksum_sha256: "checksum-#{unique}",
      storage_bucket: "test-documents",
      storage_key: "financings/#{unique}.pdf",
      source: "upload",
      status: "ready"
    })
    |> Repo.insert!()
  end
end
