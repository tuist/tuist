defmodule Tuist.License.CacheTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Tuist.Environment
  alias Tuist.License

  setup :set_mimic_global

  setup do
    Cachex.clear(:license)
    stub(Environment, :license_certificate_base64, fn -> nil end)
    stub(Environment, :license_key, fn -> "retryable-license" end)
    on_exit(fn -> Cachex.clear(:license) end)
    :ok
  end

  test "validation errors back off briefly, then recover without a day-long failure entry" do
    atlas = License.get_validation_url()
    keygen = License.get_keygen_validation_url()
    expect(Req, :post, fn ^atlas, _opts -> {:ok, %{status: 503}} end)
    expect(Req, :post, fn ^keygen, _opts -> {:ok, %{status: 503}} end)

    expect(Req, :post, fn ^atlas, _opts ->
      {:ok,
       %{
         status: 200,
         body: %{
           "data" => %{
             "id" => "recovered",
             "attributes" => %{
               "expiry" => DateTime.utc_now() |> DateTime.add(86_400) |> DateTime.to_iso8601(),
               "metadata" => %{"signingKey" => "key"}
             }
           },
           "meta" => %{"valid" => true}
         }
       }}
    end)

    assert {:error, _} = error = License.get_license()
    assert License.get_license() == error
    assert License.get_cached_license() == nil
    retry_key = "Elixir.Tuist.License-validation"
    assert Cachex.ttl(:license, retry_key) in 1..10_000
    Cachex.del(:license, retry_key)
    assert {:ok, %License{id: "recovered", valid: true}} = License.get_license()
    assert {:ok, %License{id: "recovered"}} = License.get_license()
    Cachex.clear(:tuist)
    assert {:ok, %License{id: "recovered"}} = License.get_license()
  end
end
