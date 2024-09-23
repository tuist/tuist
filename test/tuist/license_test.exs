defmodule Tuist.LicenseTest do
  use ExUnit.Case, async: false
  use Mimic

  setup :set_mimic_from_context

  alias Tuist.Environment
  alias Tuist.License

  describe "assert_valid!/0" do
    setup do
      Environment |> stub(:on_premise?, fn -> true end)
      :ok
    end

    test "returns :ok when the license is valid" do
      # Given
      cache = UUIDv7.generate() |> String.to_atom()
      {:ok, _} = Cachex.start_link(name: cache)
      validation_url = License.get_validation_url()
      expiry = DateTime.utc_now() |> DateTime.shift(day: 1) |> Timex.format!("{RFC3339}")
      license_key = UUIDv7.generate() |> String.to_atom()
      Environment |> stub(:get_license_key, fn -> license_key end)

      Req
      |> stub(:post!, fn ^validation_url, [json: %{meta: %{key: ^license_key}}] ->
        %{
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
        }
      end)

      # When
      got = License.assert_valid!(cache: cache)

      # Then
      assert got == :ok
    end

    test "raises an error when the license is absent" do
      # Given
      cache = UUIDv7.generate() |> String.to_atom()
      {:ok, _} = Cachex.start_link(name: cache)

      # When/Then
      assert_raise RuntimeError,
                   "The license key exposed through the environment variable TUIST_LICENSE or TUIST_LICENSE_KEY is missing.",
                   fn ->
                     License.assert_valid!(cache: cache)
                   end
    end

    test "raises an error when the license is invalid" do
      # Given
      cache = UUIDv7.generate() |> String.to_atom()
      {:ok, _} = Cachex.start_link(name: cache)
      validation_url = License.get_validation_url()
      expiry = DateTime.utc_now() |> DateTime.shift(day: -1) |> Timex.format!("{RFC3339}")
      license_key = UUIDv7.generate() |> String.to_atom()
      Environment |> stub(:get_license_key, fn -> license_key end)

      Req
      |> stub(:post!, fn ^validation_url, [json: %{meta: %{key: ^license_key}}] ->
        %{
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
        }
      end)

      # When/Then
      assert_raise RuntimeError,
                   "The license key is invalid or expired. Please, conctact contact@tuist.io to get a new one.",
                   fn ->
                     License.assert_valid!(cache: cache)
                   end
    end
  end
end
