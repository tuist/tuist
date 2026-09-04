defmodule Tuist.SentryTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.FeatureFlags

  setup :set_mimic_from_context

  describe "hive_reroute_target/0" do
    test "returns nil when the Hive flag is off, without consulting the DSN" do
      expect(FeatureFlags, :hive_error_tracking_enabled?, fn -> false end)
      reject(Environment, :sentry_hive_dsn, 0)

      assert Tuist.Sentry.hive_reroute_target() == nil
    end

    test "returns nil when the flag is on but no Hive DSN is configured" do
      stub(FeatureFlags, :hive_error_tracking_enabled?, fn -> true end)
      stub(Environment, :sentry_hive_dsn, fn -> nil end)

      assert Tuist.Sentry.hive_reroute_target() == nil
    end

    test "returns nil when the flag is on but the Hive DSN is blank" do
      stub(FeatureFlags, :hive_error_tracking_enabled?, fn -> true end)
      stub(Environment, :sentry_hive_dsn, fn -> "" end)

      assert Tuist.Sentry.hive_reroute_target() == nil
    end

    test "returns nil when the configured Hive DSN cannot be parsed" do
      stub(FeatureFlags, :hive_error_tracking_enabled?, fn -> true end)
      stub(Environment, :sentry_hive_dsn, fn -> "not-a-dsn" end)

      assert Tuist.Sentry.hive_reroute_target() == nil
    end

    test "returns the parsed target when the flag is on and the DSN is valid" do
      stub(FeatureFlags, :hive_error_tracking_enabled?, fn -> true end)

      stub(Environment, :sentry_hive_dsn, fn ->
        "https://310773a4be81663932ccf195e6331f0f@hive.tuist.dev/3"
      end)

      assert %{
               endpoint_uri: "https://hive.tuist.dev/api/3/envelope/",
               public_key: "310773a4be81663932ccf195e6331f0f",
               secret_key: nil
             } = Tuist.Sentry.hive_reroute_target()
    end
  end
end
