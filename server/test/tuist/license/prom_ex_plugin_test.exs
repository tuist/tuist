defmodule Tuist.License.PromExPluginTest do
  use ExUnit.Case, async: true

  alias Tuist.License
  alias Tuist.License.PromExPlugin

  test "reports a valid license and its expiration timestamp" do
    expiration_date = ~U[2029-01-31 00:00:00Z]

    assert PromExPlugin.license_status_measurements(
             {:ok,
              %License{
                id: "license",
                features: [],
                expiration_date: expiration_date,
                valid: true
              }}
           ) == %{
             expiration_timestamp_seconds: 1_864_512_000,
             valid: 1
           }
  end

  test "reports an invalid state when license resolution fails" do
    assert PromExPlugin.license_status_measurements({:error, :license_not_found}) == %{
             expiration_timestamp_seconds: 0,
             valid: 0
           }
  end
end
