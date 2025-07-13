defmodule Tuist.LicenseTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.KeyValueStore
  alias Tuist.License

  setup :set_mimic_from_context

  describe "assert_valid!/0" do
    setup do
      stub(Tuist.Environment, :test?, fn -> false end)

      stub(KeyValueStore, :get_or_update, fn _, _, func ->
        func.()
      end)

      :ok
    end

    test "returns :ok when the license is valid" do
      # Given
      validation_url = License.get_validation_url()
      expiry = DateTime.utc_now() |> DateTime.shift(day: 1) |> Timex.format!("{RFC3339}")
      license_key = String.to_atom(UUIDv7.generate())
      stub(Environment, :get_license_key, fn -> license_key end)

      stub(Req, :post, fn ^validation_url, [json: %{meta: %{key: ^license_key}}] ->
        {:ok,
         %{
           status: 200,
           body: %{
             "data" => %{
               "id" => "1234",
               "attributes" => %{
                 "expiry" => expiry
               }
             },
             "meta" => %{
               "valid" => true
             }
           }
         }}
      end)

      # When
      got = License.assert_valid!()

      # Then
      assert got == :ok
    end

    test "raises an error when the license is absent" do
      # When/Then
      assert_raise RuntimeError,
                   "The license key exposed through the environment variable TUIST_LICENSE or TUIST_LICENSE_KEY is missing.",
                   fn ->
                     License.assert_valid!()
                   end
    end

    test "raises an error when the server reports that the license is invalid" do
      # Given
      validation_url = License.get_validation_url()
      expiry = DateTime.utc_now() |> DateTime.shift(day: -1) |> Timex.format!("{RFC3339}")
      license_key = String.to_atom(UUIDv7.generate())
      stub(Environment, :get_license_key, fn -> license_key end)

      stub(Req, :post, fn ^validation_url, [json: %{meta: %{key: ^license_key}}] ->
        {:ok,
         %{
           status: 200,
           body: %{
             "data" => %{
               "id" => "1234",
               "attributes" => %{
                 "expiry" => expiry
               }
             },
             "meta" => %{
               "valid" => false
             }
           }
         }}
      end)

      # When/Then
      assert_raise RuntimeError,
                   "The license key is invalid or expired. Please, contact contact@tuist.dev to get a new one.",
                   fn ->
                     License.assert_valid!()
                   end
    end

    test "raises an error when the request to validate the license fails" do
      # Given
      validation_url = License.get_validation_url()
      license_key = String.to_atom(UUIDv7.generate())
      stub(Environment, :get_license_key, fn -> license_key end)

      stub(Req, :post, fn ^validation_url, [json: %{meta: %{key: ^license_key}}] ->
        {:ok,
         %{
           status: 500
         }}
      end)

      # When/Then
      assert_raise RuntimeError,
                   "The license validation failed with the following error: The server to validate the license responded with a 500 status code.",
                   fn ->
                     License.assert_valid!()
                   end
    end

    test "raises an error when the Req errors" do
      # Given
      validation_url = License.get_validation_url()
      license_key = String.to_atom(UUIDv7.generate())
      stub(Environment, :get_license_key, fn -> license_key end)

      stub(Req, :post, fn ^validation_url, [json: %{meta: %{key: ^license_key}}] ->
        {:error, "req error."}
      end)

      # When/Then
      assert_raise RuntimeError,
                   "The license validation failed with the following error: \"req error.\"",
                   fn ->
                     License.assert_valid!()
                   end
    end
  end
end
