defmodule Atlas.Assets.DataCentersTest do
  use Atlas.DataCase, async: true

  import Atlas.AssetsFixtures

  alias Atlas.Assets
  alias Atlas.Assets.DataCenter

  describe "create_data_center/1" do
    test "creates a data center with defaults" do
      name = "DC #{System.unique_integer([:positive])}"
      assert {:ok, %DataCenter{} = dc} = Assets.create_data_center(%{name: name, provider: "TARGO"})
      assert dc.name == name
      assert dc.status == "active"
    end

    test "rejects a blank name" do
      assert {:error, changeset} = Assets.create_data_center(%{name: ""})
      refute changeset.valid?
    end

    test "rejects duplicate names" do
      name = "Dup #{System.unique_integer([:positive])}"
      insert_data_center!(name: name)
      assert {:error, changeset} = Assets.create_data_center(%{name: name})
      refute changeset.valid?
      assert %{name: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "edit_data_center/2" do
    test "updates metadata fields" do
      dc = insert_data_center!()
      assert {:ok, updated} = Assets.edit_data_center(dc, %{city: "Frankfurt"})
      assert updated.city == "Frankfurt"
    end
  end

  describe "decommission_data_center/1" do
    test "marks an empty data center as decommissioned" do
      dc = insert_data_center!()
      assert {:ok, updated} = Assets.decommission_data_center(dc)
      assert updated.status == "decommissioned"
    end

    test "rejects decommissioning when assets are still hosted" do
      dc = insert_data_center!()
      asset = insert_asset!(location: "data_center", data_center_id: dc.id)

      assert {:error, changeset} = Assets.decommission_data_center(dc)
      refute changeset.valid?
      assert changeset.errors[:base]

      # Removing the asset unblocks decommissioning.
      {:ok, _} = Assets.edit_metadata(asset, %{location: "office", data_center_id: nil})
      assert {:ok, updated} = Assets.decommission_data_center(dc)
      assert updated.status == "decommissioned"
    end
  end

  describe "install_asset_in_data_center/3" do
    test "moves a non-DC asset into the data center" do
      dc = insert_data_center!()
      asset = insert_asset!()
      refute asset.data_center_id

      assert {:ok, updated} =
               Assets.install_asset_in_data_center(asset, dc, location_detail: "R1")

      assert updated.location == "data_center"
      assert updated.data_center_id == dc.id
      assert updated.location_detail == "R1"
    end
  end

  describe "asset ↔ data center invariant" do
    test "rejects location = data_center without a data_center_id" do
      assert {:error, changeset} =
               Assets.create_asset(asset_attrs(location: "data_center"))

      assert %{data_center_id: [_ | _]} = errors_on(changeset)
    end

    test "rejects a data_center_id on non-data-center location" do
      dc = insert_data_center!()

      assert {:error, changeset} =
               Assets.create_asset(asset_attrs(location: "office", data_center_id: dc.id))

      assert %{data_center_id: [_ | _]} = errors_on(changeset)
    end

    test "accepts location = data_center with a data_center_id" do
      dc = insert_data_center!()

      assert {:ok, asset} =
               Assets.create_asset(asset_attrs(location: "data_center", data_center_id: dc.id))

      assert asset.location == "data_center"
      assert asset.data_center_id == dc.id
    end
  end
end
