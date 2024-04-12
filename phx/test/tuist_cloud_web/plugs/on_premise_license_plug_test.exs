defmodule TuistCloudWeb.OnPremiseLicensePlugTest do
  alias TuistCloudWeb.OnPremiseLicensePlug
  use TuistCloudWeb.ConnCase
  use Plug.Test
  use Mimic

  test "returns the same connection if it's not on-premise", %{conn: conn} do
    # Given
    TuistCloud.Environment
    |> stub(:on_premise?, fn -> false end)

    opts = OnPremiseLicensePlug.init(:api)

    # When
    got = conn |> OnPremiseLicensePlug.call(opts)

    # Then
    assert got == conn
  end

  test "returns an error if the license has expired", %{conn: conn} do
    # Given
    TuistCloud.Environment
    |> stub(:on_premise?, fn -> true end)

    TuistCloud.Environment
    |> stub(:license_expired?, fn -> true end)

    opts = OnPremiseLicensePlug.init(:api)

    # When
    got = conn |> OnPremiseLicensePlug.call(opts)

    # Then
    assert json_response(got, 422) == %{
             "message" =>
               "The license has expired. Please, contact contact@tuist.io to renovate it."
           }
  end

  test "includes a warning in the connection if the license will expire in less than 30 days", %{
    conn: conn
  } do
    # Given
    TuistCloud.Environment
    |> stub(:on_premise?, fn -> true end)

    TuistCloud.Environment
    |> stub(:license_expired?, fn -> false end)

    TuistCloud.Environment
    |> stub(:license_expiration_days_span, fn -> 29 end)

    opts = OnPremiseLicensePlug.init(:api)

    # When
    got = conn |> OnPremiseLicensePlug.call(opts)

    # Then
    assert TuistCloudWeb.WarningsHeaderPlug.get_warnings(got) ==
             [
               "The license will expire in 29 days. Please, contact contact@tuist.io to renovate it."
             ]
  end
end
