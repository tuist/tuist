defmodule Atlas.Assets.AssetTest do
  use Atlas.DataCase, async: true

  import Atlas.AssetsFixtures

  alias Atlas.Assets.Asset

  describe "create_changeset/2" do
    test "accepts a fully populated laptop and normalizes strings" do
      changeset =
        Asset.create_changeset(%Asset{}, asset_attrs(%{asset_tag: "  TAG-A  ", manufacturer: "  Acme  "}))

      assert changeset.valid?
      assert get_change(changeset, :asset_tag) == "TAG-A"
      assert get_change(changeset, :manufacturer) == "Acme"
    end

    test "requires the identity and finance fields" do
      changeset = Asset.create_changeset(%Asset{}, %{})

      refute changeset.valid?

      required = [:name, :category, :purchased_on, :acquisition_cost, :acquisition_currency, :useful_life_months]

      for field <- required do
        assert %{^field => ["can't be blank"]} = errors_on(changeset)
      end
    end

    test "accepts a leased asset without purchased_on" do
      attrs =
        asset_attrs(%{ownership: "leased", ownership_acquired_on: nil})
        |> Map.delete(:purchased_on)

      changeset = Asset.create_changeset(%Asset{}, attrs)

      assert changeset.valid?
      assert get_field(changeset, :ownership) == "leased"
      assert get_field(changeset, :purchased_on) == nil
    end

    test "still requires purchased_on for an owned asset" do
      attrs = asset_attrs(%{ownership: "owned"}) |> Map.delete(:purchased_on)
      changeset = Asset.create_changeset(%Asset{}, attrs)

      assert %{purchased_on: ["can't be blank"]} = errors_on(changeset)
    end

    test "defaults ownership_acquired_on to purchased_on for an owned asset" do
      changeset =
        Asset.create_changeset(%Asset{}, asset_attrs(%{ownership: "owned"}))

      assert changeset.valid?
      assert get_field(changeset, :ownership_acquired_on) == get_field(changeset, :purchased_on)
    end

    test "rejects an unknown ownership value" do
      changeset = Asset.create_changeset(%Asset{}, asset_attrs(%{ownership: "borrowed"}))

      assert %{ownership: ["is invalid"]} = errors_on(changeset)
    end

    test "defaults useful_life_months from the category when not supplied" do
      attrs = asset_attrs(%{category: "server"}) |> Map.delete(:useful_life_months)
      changeset = Asset.create_changeset(%Asset{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :useful_life_months) == 60
    end

    test "rejects an unknown category" do
      changeset = Asset.create_changeset(%Asset{}, asset_attrs(%{category: "spaceship"}))

      assert %{category: ["is invalid"]} = errors_on(changeset)
    end

    test "rejects an unknown currency" do
      changeset = Asset.create_changeset(%Asset{}, asset_attrs(%{acquisition_currency: "XYZ"}))

      assert %{acquisition_currency: ["is not a supported ISO 4217 currency code"]} = errors_on(changeset)
    end

    test "rejects a serial number without a manufacturer" do
      changeset =
        Asset.create_changeset(
          %Asset{},
          asset_attrs(%{serial_number: "SN-123", manufacturer: nil})
        )

      assert %{manufacturer: ["is required when a serial number is set"]} = errors_on(changeset)
    end

    test "rejects negative acquisition cost" do
      changeset =
        Asset.create_changeset(%Asset{}, asset_attrs(%{acquisition_cost: Decimal.new("-1.00")}))

      assert %{acquisition_cost: ["must be zero or greater"]} = errors_on(changeset)
    end

    test "rejects salvage value greater than acquisition cost" do
      changeset =
        Asset.create_changeset(
          %Asset{},
          asset_attrs(%{acquisition_cost: Decimal.new("100"), salvage_value: Decimal.new("200")})
        )

      assert %{salvage_value: ["must be at most acquisition cost"]} = errors_on(changeset)
    end

    test "rejects zero or negative useful_life_months" do
      changeset = Asset.create_changeset(%Asset{}, asset_attrs(%{useful_life_months: 0}))

      assert %{useful_life_months: ["must be greater than 0"]} = errors_on(changeset)
    end
  end

  describe "database constraints" do
    test "unique asset_tag" do
      shared_tag = "shared-tag-#{System.unique_integer([:positive])}"
      _ = insert_asset!(%{asset_tag: shared_tag})

      {:error, changeset} =
        %Asset{}
        |> Asset.create_changeset(asset_attrs(%{asset_tag: shared_tag}))
        |> Repo.insert()

      assert %{asset_tag: ["has already been taken"]} = errors_on(changeset)
    end

    test "unique (manufacturer, serial_number)" do
      shared_serial = "SN-#{System.unique_integer([:positive])}"
      _ = insert_asset!(%{manufacturer: "AcmeCo", serial_number: shared_serial})

      {:error, changeset} =
        %Asset{}
        |> Asset.create_changeset(asset_attrs(%{manufacturer: "AcmeCo", serial_number: shared_serial}))
        |> Repo.insert()

      assert %{serial_number: ["has already been taken"]} = errors_on(changeset)
    end

    test "same serial across different manufacturers is allowed" do
      shared_serial = "SN-CROSS-#{System.unique_integer([:positive])}"
      _ = insert_asset!(%{manufacturer: "AcmeCo", serial_number: shared_serial})

      assert %Asset{} =
               insert_asset!(%{manufacturer: "OtherCo", serial_number: shared_serial})
    end
  end

  describe "metadata_changeset/2" do
    test "does not cast lifecycle-owned fields" do
      asset = insert_asset!()

      changeset =
        Asset.metadata_changeset(asset, %{
          "state" => "in_service",
          "assigned_to_id" => Ecto.UUID.generate(),
          "retired_on" => ~D[2026-06-01],
          "placed_in_service_on" => ~D[2026-05-01],
          "notes" => "updated notes"
        })

      assert get_change(changeset, :notes) == "updated notes"
      assert get_change(changeset, :state) == nil
      assert get_change(changeset, :assigned_to_id) == nil
      assert get_change(changeset, :retired_on) == nil
      assert get_change(changeset, :placed_in_service_on) == nil
    end
  end
end
