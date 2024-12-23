defmodule TuistWeb.OnPremiseLicensePlugTest do
  alias TuistWeb.OnPremiseLicensePlug
  use TuistTestSupport.Cases.ConnCase
  use Plug.Test
  use Mimic

  test "returns the same connection if it's not on-premise", %{conn: conn} do
    # Given
    Tuist.Environment
    |> stub(:on_premise?, fn -> false end)

    opts = OnPremiseLicensePlug.init(:api)

    # When
    got = conn |> OnPremiseLicensePlug.call(opts)

    # Then
    assert got == conn
  end

  test "returns a halted connection with a JSON error if the license has expired", %{conn: conn} do
    # Given
    Tuist.Environment
    |> stub(:on_premise?, fn -> true end)

    Tuist.License
    |> stub(:get_license, fn -> {:ok, %{valid: false}} end)

    opts = OnPremiseLicensePlug.init(:api)

    # When
    got = conn |> OnPremiseLicensePlug.call(opts)

    # Then
    assert got.halted == true

    assert json_response(got, 422) == %{
             "message" =>
               "The license has expired. Please, contact contact@tuist.io to renovate it."
           }
  end

  test "includes a warning in the connection if the license will expire in less than 30 days", %{
    conn: conn
  } do
    # Given
    Tuist.Environment
    |> stub(:on_premise?, fn -> true end)

    expiration_date = Tuist.Time.utc_now() |> DateTime.shift(day: 15)

    Tuist.License
    |> stub(:get_license, fn -> {:ok, %{valid: true, expiration_date: expiration_date}} end)

    opts = OnPremiseLicensePlug.init(:api)

    # When
    got = conn |> OnPremiseLicensePlug.call(opts)

    # Then
    assert TuistWeb.WarningsHeaderPlug.get_warnings(got) ==
             [
               "The license will expire in 15 days. Please, contact contact@tuist.io to renovate it."
             ]
  end

  test "returns the same connection if it's on-premise and the license will expire in more than 30 days",
       %{conn: conn} do
    # Given
    Tuist.Environment
    |> stub(:on_premise?, fn -> true end)

    expiration_date = Tuist.Time.utc_now() |> DateTime.shift(day: 35)

    Tuist.License
    |> stub(:get_license, fn -> {:ok, %{valid: true, expiration_date: expiration_date}} end)

    opts = OnPremiseLicensePlug.init(:api)

    # When
    got = conn |> OnPremiseLicensePlug.call(opts)

    # Then
    assert got == conn
  end
end
