defmodule Tuist.Environment.OpsClickHouseTest do
  use ExUnit.Case, async: true

  alias Tuist.Environment

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
