defmodule Tuist.EnvironmentRegionalDNSTest do
  use ExUnit.Case, async: true

  alias Tuist.Environment

  test "regional publication is opt-in and scoped to an explicit domain map" do
    assert Environment.kura_regional_dns_domain("ca-east", %{}) == nil
    env = %{"TUIST_KURA_REGIONAL_DNS_DOMAINS" => ~s({"ca-east":"ca-east.staging.kura.tuist.dev"})}
    assert Environment.kura_regional_dns_domain("ca-east", env) == "ca-east.staging.kura.tuist.dev"
    assert Environment.kura_regional_dns_domain("us-east", env) == nil

    for value <- [
          "",
          "invalid json",
          "[]",
          ~s({"ca-east":false}),
          ~s({"ca-east":""}),
          ~s({"ca-east":"*.kura.tuist.dev"}),
          ~s({"ca-east":"invalid/path"})
        ] do
      assert Environment.kura_regional_dns_domain("ca-east", %{"TUIST_KURA_REGIONAL_DNS_DOMAINS" => value}) == nil
    end
  end
end
