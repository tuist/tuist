defmodule Tuist.EnvironmentOriginTest do
  use ExUnit.Case, async: true

  alias Tuist.Environment

  test "Origin identity is absent until configured" do
    assert Environment.origin_app_id(%{}) == nil
    assert Environment.origin_app_private_key(%{}) == nil
  end

  test "reads the registered Origin app ID" do
    secrets = %{"origin" => %{"app" => %{"id" => "app_test"}}}

    assert Environment.origin_app_id(secrets) == "app_test"
  end

  test "preserves the multiline signing key" do
    pem = "-----BEGIN PRIVATE KEY-----\nfixture\n-----END PRIVATE KEY-----\n"
    secrets = %{"origin" => %{"app" => %{"private_key" => pem}}}

    assert Environment.origin_app_private_key(secrets) == pem
  end
end
