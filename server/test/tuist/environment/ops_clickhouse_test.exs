defmodule Tuist.Environment.OpsClickHouseTest do
  use ExUnit.Case, async: true

  alias Tuist.Environment

  test "builds an operator URL from the application endpoint and dedicated credentials" do
    application_url = "https://default:admin@clickhouse.example.com:8443/tuist?secure=true"

    assert Environment.build_ops_clickhouse_url(application_url, "tuist_ops", "s:e@cret") ==
             "https://tuist_ops:s%3Ae%40cret@clickhouse.example.com:8443/tuist?secure=true"
  end

  test "does not build an operator URL without every input" do
    assert Environment.build_ops_clickhouse_url("https://clickhouse.example.com/tuist", nil, nil) == nil
  end

  test "accepts a distinct operator user" do
    ops_url = "https://tuist_ops:secret@clickhouse.example.com:8443/tuist"
    application_url = "https://tuist_app:secret@clickhouse.example.com:8443/tuist"

    assert Environment.validate_ops_clickhouse_url!(ops_url, application_url) == ops_url
  end

  test "rejects the application user" do
    url = "https://tuist_app:secret@clickhouse.example.com:8443/tuist"

    assert_raise RuntimeError,
                 "TUIST_OPS_CLICKHOUSE_URL must not reuse the application ClickHouse user",
                 fn ->
                   Environment.validate_ops_clickhouse_url!(url, url)
                 end
  end

  test "rejects a connection string without a username" do
    ops_url = "https://clickhouse.example.com:8443/tuist"
    application_url = "https://tuist_app:secret@clickhouse.example.com:8443/tuist"

    assert_raise RuntimeError,
                 "TUIST_OPS_CLICKHOUSE_URL must include a dedicated username",
                 fn ->
                   Environment.validate_ops_clickhouse_url!(ops_url, application_url)
                 end
  end

  test "treats an application connection without a username as the default user" do
    ops_url = "https://default:secret@clickhouse.example.com:8443/tuist"
    application_url = "https://clickhouse.example.com:8443/tuist"

    assert_raise RuntimeError,
                 "TUIST_OPS_CLICKHOUSE_URL must not reuse the application ClickHouse user",
                 fn ->
                   Environment.validate_ops_clickhouse_url!(ops_url, application_url)
                 end
  end
end
