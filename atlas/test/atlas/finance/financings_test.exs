defmodule Atlas.Finance.FinancingsTest do
  use Atlas.DataCase, async: true

  import Atlas.AssetsFixtures
  import Atlas.FinanceFixtures
  import Atlas.FinancingsFixtures

  alias Atlas.Assets
  alias Atlas.Assets.Asset
  alias Atlas.Finance.Financing
  alias Atlas.Finance.Financings

  describe "create/1" do
    test "creates a loan" do
      assert {:ok, %Financing{}} = Financings.create(loan_attrs())
    end

    test "creates a lease with option" do
      assert {:ok, %Financing{}} = Financings.create(lease_with_option_attrs())
    end

    test "returns an error changeset when required fields are missing" do
      assert {:error, changeset} = Financings.create(%{})
      refute changeset.valid?
    end
  end

  describe "set_accounting_treatment/3" do
    test "records treatment and evidence" do
      {:ok, financing} = Financings.create(loan_attrs())

      assert {:ok, updated} =
               Financings.set_accounting_treatment(financing, "capitalized", "Approved by KPMG")

      assert updated.accounting_treatment == "capitalized"
      assert updated.treatment_evidence == "Approved by KPMG"
    end

    test "rejects an unknown treatment" do
      {:ok, financing} = Financings.create(loan_attrs())

      assert {:error, changeset} = Financings.set_accounting_treatment(financing, "bogus", nil)
      refute changeset.valid?
    end
  end

  describe "set_lines/2" do
    test "accepts a full 10_000 bps set" do
      {:ok, financing} = Financings.create(lease_with_option_attrs())
      asset_a = insert_asset!()
      asset_b = insert_asset!()

      assert {:ok, lines} =
               Financings.set_lines(financing, [
                 %{asset_id: asset_a.id, share_bps: 5_000},
                 %{asset_id: asset_b.id, share_bps: 5_000}
               ])

      assert length(lines) == 2
    end

    test "rejects a partial set" do
      {:ok, financing} = Financings.create(lease_with_option_attrs())
      asset = insert_asset!()

      assert {:error, changeset} =
               Financings.set_lines(financing, [%{asset_id: asset.id, share_bps: 5_000}])

      assert errors_on(changeset)[:status]
    end

    test "atomic replacement wipes the old set" do
      {:ok, financing} = Financings.create(lease_with_option_attrs())
      a = insert_asset!()
      b = insert_asset!()
      c = insert_asset!()

      {:ok, _} =
        Financings.set_lines(financing, [
          %{asset_id: a.id, share_bps: 5_000},
          %{asset_id: b.id, share_bps: 5_000}
        ])

      assert {:ok, _} = Financings.set_lines(financing, [%{asset_id: c.id, share_bps: 10_000}])

      lines = Financings.list_lines(financing)
      assert length(lines) == 1
      assert hd(lines).asset_id == c.id
    end
  end

  describe "exercise_option/2" do
    setup do
      {:ok, financing} = Financings.create(lease_with_option_attrs())
      asset = insert_asset!(%{ownership: "leased", ownership_acquired_on: nil})
      _ = Map.delete(asset, :purchased_on)

      {:ok, _} = Financings.set_lines(financing, [%{asset_id: asset.id, share_bps: 10_000}])

      source = insert_finance_source!()
      account = insert_finance_account!(source)

      option_txn =
        insert_finance_transaction!(account, %{
          amount_value: financing.purchase_option_amount,
          amount_currency: financing.currency,
          direction: "debit"
        })

      %{financing: financing, asset: asset, option_txn: option_txn}
    end

    test "flips ownership and preserves identity",
         %{financing: financing, asset: asset, option_txn: txn} do
      assert {:ok, updated_financing} =
               Financings.exercise_option(financing,
                 on: ~D[2029-02-01],
                 option_transaction_id: txn.id
               )

      assert updated_financing.status == "option_exercised"

      refreshed = Assets.get_asset!(asset.id)
      assert refreshed.ownership == "owned"
      assert refreshed.ownership_acquired_on == ~D[2029-02-01]
      # placed_in_service_on and acquisition_cost preserved.
      assert refreshed.placed_in_service_on == asset.placed_in_service_on
      assert Decimal.equal?(refreshed.acquisition_cost, asset.acquisition_cost)
    end

    test "rejects cross-currency exercise",
         %{financing: financing, asset: _asset} do
      source = insert_finance_source!()
      account = insert_finance_account!(source, %{currency: "USD"})

      usd_txn =
        insert_finance_transaction!(account, %{
          amount_value: financing.purchase_option_amount,
          amount_currency: "USD",
          direction: "debit"
        })

      assert {:error, changeset} =
               Financings.exercise_option(financing,
                 on: ~D[2029-02-01],
                 option_transaction_id: usd_txn.id
               )

      assert errors_on(changeset)[:status] |> List.first() =~ "cross-currency"
    end

    test "rejects a credit transaction", %{financing: financing} do
      source = insert_finance_source!()
      account = insert_finance_account!(source)

      credit_txn =
        insert_finance_transaction!(account, %{
          amount_value: financing.purchase_option_amount,
          amount_currency: financing.currency,
          direction: "credit"
        })

      assert {:error, changeset} =
               Financings.exercise_option(financing,
                 on: ~D[2029-02-01],
                 option_transaction_id: credit_txn.id
               )

      assert errors_on(changeset)[:status] |> List.first() =~ "debit"
    end
  end

  describe "return/2" do
    test "transitions the asset to :returned_to_lessor" do
      {:ok, financing} = Financings.create(lease_with_option_attrs())
      asset = insert_asset!(%{ownership: "leased"})

      {:ok, _} = Financings.set_lines(financing, [%{asset_id: asset.id, share_bps: 10_000}])

      assert {:ok, returned} = Financings.return(financing, on: ~D[2029-02-01])
      assert returned.status == "returned"

      assert %Asset{state: "returned_to_lessor"} = Assets.get_asset!(asset.id)
    end

    test "loans cannot be returned" do
      {:ok, financing} = Financings.create(loan_attrs())
      assert {:error, changeset} = Financings.return(financing, on: ~D[2026-06-01])
      assert errors_on(changeset)[:status] |> List.first() =~ "loans"
    end
  end

  describe "terminate/2" do
    test "loan terminate does not touch the asset" do
      {:ok, financing} = Financings.create(loan_attrs())
      asset = insert_asset!()

      {:ok, _} = Financings.set_lines(financing, [%{asset_id: asset.id, share_bps: 10_000}])

      assert {:ok, terminated} = Financings.terminate(financing, on: ~D[2026-06-01])
      assert terminated.status == "terminated"

      assert %Asset{state: state} = Assets.get_asset!(asset.id)
      assert state != "returned_to_lessor"
    end

    test "lease terminate returns the assets" do
      {:ok, financing} = Financings.create(lease_with_option_attrs())
      asset = insert_asset!(%{ownership: "leased"})

      {:ok, _} = Financings.set_lines(financing, [%{asset_id: asset.id, share_bps: 10_000}])

      assert {:ok, _} = Financings.terminate(financing, on: ~D[2026-06-01])
      assert %Asset{state: "returned_to_lessor"} = Assets.get_asset!(asset.id)
    end
  end
end
