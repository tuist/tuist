defmodule TuistWeb.OnPremiseLicensePlugTest do
  alias TuistWeb.OnPremiseLicensePlug
  use TuistWeb.ConnCase
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
    |> stub(:valid?, fn -> false end)

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

    Tuist.License
    |> stub(:valid?, fn -> true end)

    Tuist.License
    |> stub(:expiration_days_span, fn -> 29 end)

    opts = OnPremiseLicensePlug.init(:api)

    # When
    got = conn |> OnPremiseLicensePlug.call(opts)

    # Then
    assert TuistWeb.WarningsHeaderPlug.get_warnings(got) ==
             [
               "The license will expire in 29 days. Please, contact contact@tuist.io to renovate it."
             ]
  end

  test "returns the same connection if it's on-premise and the license will expire in more than 30 days",
       %{conn: conn} do
    # Given
    Tuist.Environment
    |> stub(:on_premise?, fn -> true end)

    Tuist.License
    |> stub(:valid?, fn -> true end)

    Tuist.License
    |> stub(:expiration_days_span, fn -> 120 end)

    opts = OnPremiseLicensePlug.init(:api)

    # When
    got = conn |> OnPremiseLicensePlug.call(opts)

    # Then
    assert got == conn
  end
end
