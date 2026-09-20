defmodule Atlas.MCP.Tools.AssetsToolsTest do
  use Atlas.MCP.ToolCase

  import Atlas.AssetsFixtures
  import Atlas.FinancingsFixtures

  alias Atlas.Assets
  alias Atlas.Finance.Financings
  alias Atlas.MCP.Tools.AssignAsset
  alias Atlas.MCP.Tools.CreateAsset
  alias Atlas.MCP.Tools.DeleteAsset
  alias Atlas.MCP.Tools.DisposeAsset
  alias Atlas.MCP.Tools.EditAssetMetadata
  alias Atlas.MCP.Tools.GetAsset
  alias Atlas.MCP.Tools.GetAssetBookValue
  alias Atlas.MCP.Tools.ListAssetAssignments
  alias Atlas.MCP.Tools.ListAssetEvents
  alias Atlas.MCP.Tools.ListAssetFinancings
  alias Atlas.MCP.Tools.ListAssets
  alias Atlas.MCP.Tools.RecordAssetRepair
  alias Atlas.MCP.Tools.RecordAssetWarrantyExtension
  alias Atlas.MCP.Tools.RetireAsset
  alias Atlas.MCP.Tools.ReturnAsset

  test "list_assets returns the current fleet as executive" do
    _ = insert_asset!(%{name: "Server X"})
    _ = insert_asset!(%{name: "Laptop Y"})

    assert {:ok, %{assets: assets, count: count}} =
             execute_tool(ListAssets, executive_mcp_conn(), %{})

    assert count == length(assets)
    assert count >= 2
    assert Enum.any?(assets, &(&1.name == "Server X"))
  end

  test "list_assets denies non-executive callers" do
    non_exec = insert_user!()

    assert {:error, message} =
             ListAssets.execute(mcp_conn(non_exec), %{})

    assert message =~ "executives"
  end

  test "list_assets narrows the fleet by category" do
    server = insert_asset!(%{name: "CI runner", category: "server"})
    _laptop = insert_asset!(%{name: "MBP", category: "laptop"})

    assert {:ok, %{assets: assets, count: count}} =
             execute_tool(ListAssets, executive_mcp_conn(), %{"category" => "server"})

    assert count == length(assets)
    assert Enum.all?(assets, &(&1.category == "server"))
    assert Enum.any?(assets, &(&1.id == server.id))
  end

  test "list_assets searches by serial number" do
    asset = insert_asset!(%{name: "Mac mini", serial_number: "MAC-#{System.unique_integer([:positive])}"})

    assert {:ok, %{assets: [result], count: 1}} =
             execute_tool(ListAssets, executive_mcp_conn(), %{"query" => asset.serial_number})

    assert result.id == asset.id
  end

  test "lists the financing connected to an asset" do
    asset = insert_asset!(%{name: "Mac mini", ownership: "leased"})
    financing = insert_financing!(%{provider: "Targo", supplier: "Apple"})
    {:ok, _lines} = Financings.set_lines(financing, [%{asset_id: asset.id, share_bps: 10_000}])

    assert {:ok, %{financings: [result], count: 1}} =
             execute_tool(ListAssetFinancings, executive_mcp_conn(), %{"asset_id" => asset.id})

    assert result.financing_id == financing.id
    assert result.provider == "Targo"
    assert result.supplier == "Apple"
    assert result.share_basis_points == 10_000
  end

  test "get_asset returns a fully serialized asset" do
    asset = insert_asset!(%{name: "MBP"})

    assert {:ok, payload} =
             execute_tool(GetAsset, executive_mcp_conn(), %{"asset_id" => asset.id})

    assert payload.id == asset.id
    assert payload.name == "MBP"
    assert payload.hardware_url =~ "/operations/hardware/#{asset.id}"
  end

  test "create_asset accepts a minimal payload and returns the created asset" do
    args = %{
      "name" => "test-server",
      "category" => "server",
      "purchased_on" => "2026-01-15",
      "acquisition_cost" => "1234.56",
      "acquisition_currency" => "EUR",
      "manufacturer" => "Acme",
      "serial_number" => "SN-#{System.unique_integer([:positive])}"
    }

    assert {:ok, payload} = execute_tool(CreateAsset, executive_mcp_conn(), args)
    assert payload.name == "test-server"
    assert payload.category == "server"
    assert payload.acquisition_currency == "EUR"
    assert payload.useful_life_months == 60
  end

  test "assign_asset opens an assignment and returns the updated asset" do
    asset = insert_asset!()
    user = insert_user_for_asset!()

    assert {:ok, payload} =
             execute_tool(AssignAsset, executive_mcp_conn(), %{
               "asset_id" => asset.id,
               "user_id" => user.id,
               "on" => "2026-04-01"
             })

    assert payload.state == "in_service"
    assert payload.assigned_to_id == user.id
  end

  test "return_asset closes the open assignment" do
    asset = insert_asset!()
    user = insert_user_for_asset!()
    {:ok, _} = Assets.assign(asset, user, on: ~D[2026-04-01])

    assert {:ok, payload} =
             execute_tool(ReturnAsset, executive_mcp_conn(), %{
               "asset_id" => asset.id,
               "on" => "2026-06-01"
             })

    assert payload.state == "in_storage"
    assert payload.assigned_to_id == nil
  end

  test "retire_asset and dispose_asset flow" do
    asset = insert_asset!()

    assert {:ok, retired} =
             execute_tool(RetireAsset, executive_mcp_conn(), %{
               "asset_id" => asset.id,
               "on" => "2026-06-01"
             })

    assert retired.state == "retired"

    assert {:ok, disposed} =
             execute_tool(DisposeAsset, executive_mcp_conn(), %{
               "asset_id" => asset.id,
               "on" => "2026-06-15",
               "proceeds" => "125.00",
               "currency" => "EUR"
             })

    assert disposed.state == "disposed"
  end

  test "record_asset_repair records an event with expenditure" do
    asset = insert_asset!()

    assert {:ok, event} =
             execute_tool(RecordAssetRepair, executive_mcp_conn(), %{
               "asset_id" => asset.id,
               "occurred_on" => "2026-05-01",
               "expenditure" => "89.00",
               "expenditure_currency" => "EUR",
               "notes" => "keyboard swap",
               "client_reference" => "repair-#{System.unique_integer([:positive])}"
             })

    assert event.event_type == "repaired"
    assert event.expenditure == "89.00"
    assert event.expenditure_currency == "EUR"
  end

  test "record_asset_warranty_extension updates the asset's warranty and records the event" do
    asset = insert_asset!(%{warranty_end_on: ~D[2027-01-15]})

    assert {:ok, event} =
             execute_tool(RecordAssetWarrantyExtension, executive_mcp_conn(), %{
               "asset_id" => asset.id,
               "occurred_on" => "2026-11-01",
               "new_warranty_end_on" => "2028-01-15",
               "expenditure" => "199.00",
               "expenditure_currency" => "EUR",
               "notes" => "AppleCare renewal"
             })

    assert event.event_type == "warranty_extended"
    assert event.previous_warranty_end_on == "2027-01-15"
    assert event.new_warranty_end_on == "2028-01-15"

    refreshed = Assets.get_asset!(asset.id)
    assert refreshed.warranty_end_on == ~D[2028-01-15]
  end

  test "list_asset_assignments returns the custody history" do
    asset = insert_asset!()
    user = insert_user_for_asset!()
    {:ok, _} = Assets.assign(asset, user, on: ~D[2026-04-01])

    assert {:ok, %{assignments: [assignment | _], count: count}} =
             execute_tool(ListAssetAssignments, executive_mcp_conn(), %{"asset_id" => asset.id})

    assert count >= 1
    assert assignment.user_id == user.id
  end

  test "list_asset_events returns the recorded events" do
    asset = insert_asset!()
    {:ok, _} = Assets.record_repair(asset, %{occurred_on: ~D[2026-05-01], notes: "n"})

    assert {:ok, %{events: [event | _], count: count}} =
             execute_tool(ListAssetEvents, executive_mcp_conn(), %{"asset_id" => asset.id})

    assert count >= 1
    assert event.event_type == "repaired"
  end

  test "edit_asset_metadata updates non-lifecycle fields" do
    asset = insert_asset!(%{name: "before"})

    assert {:ok, payload} =
             execute_tool(EditAssetMetadata, executive_mcp_conn(), %{
               "asset_id" => asset.id,
               "name" => "after",
               "vendor" => "Acme"
             })

    assert payload.name == "after"
  end

  test "delete_asset removes an asset with no history" do
    asset = insert_asset!()

    assert {:ok, %{deleted: true, asset_id: id}} =
             execute_tool(DeleteAsset, executive_mcp_conn(), %{"asset_id" => asset.id})

    assert id == asset.id
    assert Assets.get_asset(asset.id) == nil
  end

  test "delete_asset refuses when the asset has history" do
    asset = insert_asset!()
    user = insert_user_for_asset!()
    {:ok, _} = Assets.assign(asset, user, on: ~D[2026-04-01])

    assert {:error, message} =
             execute_tool(DeleteAsset, executive_mcp_conn(), %{"asset_id" => asset.id})

    assert message =~ "assignment"
  end

  test "get_asset_book_value returns the current estimated value" do
    {:ok, asset} =
      Assets.create_asset(
        asset_attrs(%{
          purchased_on: ~D[2026-01-01],
          acquisition_cost: Decimal.new("3600.00"),
          useful_life_months: 36
        })
      )

    {:ok, _} = Assets.place_in_service(asset, on: ~D[2026-01-01])

    assert {:ok, %{value: value, currency: "EUR", excluded_reason: nil}} =
             execute_tool(GetAssetBookValue, executive_mcp_conn(), %{
               "asset_id" => asset.id,
               "on" => "2026-01-01"
             })

    assert value == "3600.00"
  end
end
