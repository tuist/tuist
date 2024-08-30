defmodule Tuist.LicenseTest do
  use ExUnit.Case
  use Mimic
  alias Tuist.Native
  alias Tuist.License

  describe "valid?/0" do
    test "returns false when the local license is invalid" do
      # Given
      Native
      |> stub(:local_license, fn ->
        {:ok,
         %Tuist.Native.License{
           id: "id",
           features: [],
           expiration_date: "2022-01-01",
           valid: false
         }}
      end)

      # When
      got = License.valid?()

      # Then
      assert got == false
    end

    test "returns true when the local license is valid" do
      # Given
      Native
      |> stub(:local_license, fn ->
        {:ok,
         %Tuist.Native.License{
           id: "id",
           features: [],
           expiration_date: "2022-01-01",
           valid: true
         }}
      end)

      # When
      got = License.valid?()

      # Then
      assert got == true
    end

    test "returns true if the local license can't be obtained and the keygen license is valid" do
      # Given
      Native
      |> stub(:local_license, fn ->
        {:error, "Invalid local license"}
      end)

      Native
      |> stub(:keygen_license, fn ->
        {:ok,
         %Tuist.Native.License{
           id: "id",
           features: [],
           expiration_date: "2022-01-01",
           valid: true
         }}
      end)

      # When
      got = License.valid?()

      # Then
      assert got == true
    end

    test "returns false if the local license can't be obtained and the keygen license is invalid" do
      # Given
      Native
      |> stub(:local_license, fn ->
        {:error, "Invalid local license"}
      end)

      Native
      |> stub(:keygen_license, fn ->
        {:ok,
         %Tuist.Native.License{
           id: "id",
           features: [],
           expiration_date: "2022-01-01",
           valid: false
         }}
      end)

      # When
      got = License.valid?()

      # Then
      assert got == false
    end
  end

  describe "expiration_days_span/0" do
    test "returns the difference between the expiration date and today" do
      # Given
      Tuist.Time
      |> stub(:utc_now, fn -> DateTime.from_naive!(~N[2021-01-01 00:00:00], "Etc/UTC") end)

      Native
      |> stub(:local_license, fn ->
        {:ok,
         %Tuist.Native.License{
           id: "id",
           features: [],
           expiration_date: "2022-01-01",
           valid: true
         }}
      end)

      # When
      got = License.expiration_days_span()

      # Then
      assert got == 365
    end
  end
end
