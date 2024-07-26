defmodule Tuist.Native.LicenseTest do
  alias Tuist.Native.License
  use Tuist.DataCase
  use Mimic

  test "license has none as expiration_date" do
    license = %License{expiration_date: "none"}

    # When / Then
    refute License.expired?(license)
  end

  test "license is not expired" do
    # Given
    Tuist.Date
    |> stub(:utc_today, fn -> ~D[2024-04-28] end)

    license = %License{expiration_date: "2024-05-04"}

    # When / Then
    refute License.expired?(license)
  end

  test "license is expired" do
    # Given
    Tuist.Date
    |> stub(:utc_today, fn -> ~D[2024-05-05] end)

    license = %License{expiration_date: "2024-05-04"}

    # When / Then
    assert License.expired?(license)
  end
end
