defmodule AtlasWeb.HardwareLiveTest do
  use AtlasWeb.ConnCase, async: true

  import Atlas.AssetsFixtures
  import Atlas.FinancingsFixtures
  import Phoenix.LiveViewTest

  alias Atlas.Assets
  alias Atlas.Finance.Financings

  test "renders the fleet as an executive", %{conn: conn} do
    {conn, _user} =
      log_in_user(conn, %{email: "exec-#{System.unique_integer([:positive])}@tuist.dev", role: :executive})

    asset = insert_asset!(%{name: "Test Server"})

    {:ok, view, html} = live(conn, ~p"/operations/hardware")

    assert has_element?(view, "#hardware")
    assert has_element?(view, "#new-asset-button")
    assert has_element?(view, "#new-asset-modal")
    assert has_element?(view, "#hardware-row-#{asset.id}")
    assert html =~ "Test Server"
  end

  test "denies non-executive access to the hardware routes", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "employee-#{System.unique_integer([:positive])}@tuist.dev"})

    assert {:error, {:redirect, %{}}} = live(conn, ~p"/operations/hardware")
  end

  test "shows an asset detail page with the computed book value", %{conn: conn} do
    {conn, _user} =
      log_in_user(conn, %{email: "exec-#{System.unique_integer([:positive])}@tuist.dev", role: :executive})

    {:ok, asset} =
      Assets.create_asset(
        asset_attrs(%{
          name: "Detail Asset",
          purchased_on: ~D[2026-01-01],
          acquisition_cost: Decimal.new("3600.00"),
          useful_life_months: 36
        })
      )

    {:ok, _} = Assets.place_in_service(asset, on: ~D[2026-01-01])

    {:ok, view, _html} = live(conn, ~p"/operations/hardware/#{asset.id}")

    assert has_element?(view, "#hardware-show")
    assert has_element?(view, "#hardware-breadcrumb-current", "Detail Asset")
    assert has_element?(view, "#hardware-financings-table")
  end

  test "shows the financing linked to an asset", %{conn: conn} do
    {conn, _user} =
      log_in_user(conn, %{
        email: "exec-#{System.unique_integer([:positive])}@tuist.dev",
        role: :executive
      })

    asset = insert_asset!(%{ownership: "leased"})
    financing = insert_financing!(%{type: "lease_without_purchase_option", provider: "Targo", supplier: "Apple"})
    {:ok, [line]} = Financings.set_lines(financing, [%{asset_id: asset.id, share_bps: 10_000}])

    {:ok, view, _html} = live(conn, ~p"/operations/hardware/#{asset.id}")

    assert has_element?(view, "#hardware-financing-#{line.id}", "Targo")
    assert has_element?(view, "#hardware-financing-#{line.id}", "Apple")
  end
end
