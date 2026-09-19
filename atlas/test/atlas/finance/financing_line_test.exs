defmodule Atlas.Finance.FinancingLineTest do
  use Atlas.DataCase, async: true

  import Atlas.AssetsFixtures
  import Atlas.FinancingsFixtures

  alias Atlas.Finance.FinancingLine
  alias Atlas.Repo

  setup do
    %{financing: insert_financing!(), asset: insert_asset!()}
  end

  test "accepts a valid share", %{financing: financing, asset: asset} do
    assert %FinancingLine{} = insert_line!(financing, asset, 10_000)
  end

  test "rejects share_bps outside [1, 10_000]", %{financing: financing, asset: asset} do
    changeset =
      FinancingLine.changeset(%FinancingLine{}, %{
        financing_id: financing.id,
        asset_id: asset.id,
        share_bps: 0
      })

    refute changeset.valid?
    assert errors_on(changeset)[:share_bps]

    changeset2 =
      FinancingLine.changeset(%FinancingLine{}, %{
        financing_id: financing.id,
        asset_id: asset.id,
        share_bps: 10_001
      })

    refute changeset2.valid?
    assert errors_on(changeset2)[:share_bps]
  end

  test "rejects a second line for the same asset on the same financing", %{
    financing: financing,
    asset: asset
  } do
    _ = insert_line!(financing, asset, 5_000)

    {:error, changeset} =
      %FinancingLine{}
      |> FinancingLine.changeset(%{
        financing_id: financing.id,
        asset_id: asset.id,
        share_bps: 5_000
      })
      |> Repo.insert()

    assert errors_on(changeset)[:financing_id] == ["has already been taken"]
  end
end
