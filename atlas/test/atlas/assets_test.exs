defmodule Atlas.AssetsTest do
  use Atlas.DataCase, async: true

  import Atlas.AssetsFixtures

  alias Atlas.Assets
  alias Atlas.Assets.Asset

  describe "create_asset/1" do
    test "creates a new asset with lifecycle-owned fields ignored" do
      assert {:ok, %Asset{} = asset} = Assets.create_asset(asset_attrs())
      assert asset.state == "in_storage"
      assert asset.assigned_to_id == nil
      assert asset.placed_in_service_on == nil
    end

    test "returns an error changeset for invalid attrs" do
      assert {:error, changeset} = Assets.create_asset(%{})
      refute changeset.valid?
    end
  end

  describe "assign/3" do
    setup do
      %{asset: insert_asset!(), user: insert_user_for_asset!()}
    end

    test "moves an in_storage asset into service and opens an assignment", %{asset: asset, user: user} do
      assert {:ok, updated} = Assets.assign(asset, user, on: ~D[2026-04-01])
      assert updated.state == "in_service"
      assert updated.assigned_to_id == user.id
      assert updated.placed_in_service_on == ~D[2026-04-01]

      {open_assignments, _meta} = Assets.list_assignments(updated)
      assert Enum.any?(open_assignments, &is_nil(&1.returned_on))
    end

    test "rejects a second concurrent open assignment", %{asset: asset, user: user} do
      another = insert_user_for_asset!()
      {:ok, _} = Assets.assign(asset, user, on: ~D[2026-04-01])

      assert {:error, changeset} = Assets.assign(asset, another, on: ~D[2026-04-05])
      assert errors_on(changeset)[:state] |> List.first() =~ "already has an open assignment"
    end
  end

  describe "return_asset/2" do
    setup do
      user = insert_user_for_asset!()
      {:ok, asset} = Assets.assign(insert_asset!(), user, on: ~D[2026-04-01])

      %{asset: asset, user: user}
    end

    test "closes the open assignment and moves the asset to in_storage", %{asset: asset} do
      assert {:ok, returned} = Assets.return_asset(asset, on: ~D[2026-06-01])
      assert returned.state == "in_storage"
      assert returned.assigned_to_id == nil

      {[latest | _], _meta} = Assets.list_assignments(returned)
      assert latest.returned_on == ~D[2026-06-01]
    end

    test "rejects returning an asset with no open assignment", %{asset: asset} do
      {:ok, _} = Assets.return_asset(asset, on: ~D[2026-06-01])
      assert {:error, changeset} = Assets.return_asset(asset, on: ~D[2026-06-15])
      assert errors_on(changeset)[:state] |> List.first() =~ "not currently in service"
    end
  end

  describe "repair lifecycle" do
    test "records pre_repair_state and restores on repaired" do
      user = insert_user_for_asset!()
      {:ok, asset} = Assets.assign(insert_asset!(), user, on: ~D[2026-04-01])

      assert {:ok, in_repair} = Assets.mark_in_repair(asset, on: ~D[2026-05-01])
      assert in_repair.state == "in_repair"
      assert in_repair.pre_repair_state == "in_service"

      assert {:ok, repaired} = Assets.mark_repaired(in_repair, on: ~D[2026-05-15])
      assert repaired.state == "in_service"
      assert repaired.pre_repair_state == nil
    end

    test "rejects marking an asset in repair twice" do
      user = insert_user_for_asset!()
      {:ok, asset} = Assets.assign(insert_asset!(), user, on: ~D[2026-04-01])
      {:ok, in_repair} = Assets.mark_in_repair(asset, on: ~D[2026-05-01])

      assert {:error, changeset} = Assets.mark_in_repair(in_repair, on: ~D[2026-05-02])
      assert errors_on(changeset)[:state] |> List.first() =~ "already in repair"
    end
  end

  describe "loss and recovery" do
    test "records pre_loss_state and restores to it on recover" do
      user = insert_user_for_asset!()
      {:ok, asset} = Assets.assign(insert_asset!(), user, on: ~D[2026-04-01])

      assert {:ok, lost} = Assets.mark_lost(asset, on: ~D[2026-05-01])
      assert lost.state == "lost"
      assert lost.pre_loss_state == "in_service"
      assert lost.lost_on == ~D[2026-05-01]

      assert {:ok, recovered} = Assets.recover(lost, on: ~D[2026-06-01])
      assert recovered.state == "in_service"
      assert recovered.pre_loss_state == nil
      assert recovered.recovered_on == ~D[2026-06-01]
    end

    test "second loss clears the previous recovered_on" do
      user = insert_user_for_asset!()
      {:ok, asset} = Assets.assign(insert_asset!(), user, on: ~D[2026-04-01])
      {:ok, lost} = Assets.mark_lost(asset, on: ~D[2026-05-01])
      {:ok, recovered} = Assets.recover(lost, on: ~D[2026-05-15])

      assert {:ok, second_loss} = Assets.mark_lost(recovered, on: ~D[2026-05-20])
      assert second_loss.state == "lost"
      assert second_loss.recovered_on == nil
      assert second_loss.lost_on == ~D[2026-05-20]
    end
  end

  describe "retirement and disposal" do
    test "retire closes an open assignment and clears holder" do
      user = insert_user_for_asset!()
      {:ok, asset} = Assets.assign(insert_asset!(), user, on: ~D[2026-04-01])

      assert {:ok, retired} = Assets.retire(asset, on: ~D[2026-06-01])
      assert retired.state == "retired"
      assert retired.assigned_to_id == nil
      assert retired.retired_on == ~D[2026-06-01]
    end

    test "dispose requires the asset to be retired" do
      asset = insert_asset!()
      assert {:error, changeset} = Assets.dispose(asset, on: ~D[2026-06-01])
      assert errors_on(changeset)[:state] |> List.first() =~ "must be retired"
    end

    test "dispose records proceeds and currency" do
      {:ok, retired} = Assets.retire(insert_asset!(), on: ~D[2026-06-01])

      assert {:ok, disposed} =
               Assets.dispose(retired,
                 on: ~D[2026-06-15],
                 proceeds: Decimal.new("250.00"),
                 currency: "EUR"
               )

      assert disposed.state == "disposed"
      assert Decimal.equal?(disposed.disposal_proceeds, Decimal.new("250.00"))
      assert disposed.disposal_currency == "EUR"
    end
  end

  describe "record_warranty_extension/2" do
    test "atomically updates warranty_end_on and inserts the event" do
      asset = insert_asset!(%{warranty_end_on: ~D[2027-01-15]})

      assert {:ok, event} =
               Assets.record_warranty_extension(asset, %{
                 occurred_on: ~D[2026-11-01],
                 new_warranty_end_on: ~D[2028-01-15],
                 expenditure: Decimal.new("199.00"),
                 expenditure_currency: "EUR",
                 notes: "AppleCare renewal"
               })

      assert event.previous_warranty_end_on == ~D[2027-01-15]
      assert event.new_warranty_end_on == ~D[2028-01-15]

      updated = Assets.get_asset!(asset.id)
      assert updated.warranty_end_on == ~D[2028-01-15]
    end

    test "rejects a new end date on or before the previous one" do
      asset = insert_asset!(%{warranty_end_on: ~D[2027-01-15]})

      assert {:error, changeset} =
               Assets.record_warranty_extension(asset, %{
                 occurred_on: ~D[2026-11-01],
                 new_warranty_end_on: ~D[2027-01-15]
               })

      refute changeset.valid?
    end
  end

  describe "record_repair/2" do
    test "idempotent when a client_reference is provided" do
      asset = insert_asset!()
      attrs = %{occurred_on: ~D[2026-05-01], notes: "keyboard swap", client_reference: "ref-1"}

      assert {:ok, first} = Assets.record_repair(asset, attrs)

      assert {:error, changeset} = Assets.record_repair(asset, attrs)
      refute changeset.valid?
      assert first.id
    end
  end

  describe "book_value_report/1" do
    test "groups totals by category and currency without mixing currencies" do
      {:ok, eur_asset} =
        Assets.create_asset(asset_attrs(%{name: "eur-laptop", acquisition_cost: Decimal.new("3000.00")}))

      {:ok, usd_asset} =
        Assets.create_asset(
          asset_attrs(%{
            name: "usd-laptop",
            acquisition_cost: Decimal.new("2500.00"),
            acquisition_currency: "USD"
          })
        )

      {:ok, _eur} = Assets.place_in_service(eur_asset, on: ~D[2026-03-01])
      {:ok, _usd} = Assets.place_in_service(usd_asset, on: ~D[2026-03-01])

      report = Assets.book_value_report(on: ~D[2027-03-01])

      assert Map.has_key?(report, {"laptop", "EUR"})
      assert Map.has_key?(report, {"laptop", "USD"})
      refute Map.has_key?(report, {"laptop", "mixed"})
    end
  end
end
