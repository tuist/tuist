defmodule Atlas.Finance.ConfigTest do
  use ExUnit.Case, async: true

  alias Atlas.Finance.Config

  test "normalizes configured sources and drops invalid entries" do
    config = [
      sources: [
        %{key: " qonto-main ", provider: :qonto, name: " Qonto Main "},
        %{key: "mercury-main", provider: " Mercury "},
        %{key: "", provider: :qonto, name: "Ignored"},
        %{key: "missing-provider", provider: nil},
        %{key: "unsupported-provider", provider: "new_bank"}
      ]
    ]

    assert [
             %{key: "qonto-main", provider: :qonto, name: "Qonto Main"},
             %{key: "mercury-main", provider: :mercury, name: "Mercury"}
           ] = Config.configured_sources(config)

    assert Config.configured_source_keys(config) == ["qonto-main", "mercury-main"]
  end

  test "fetches a configured source by key" do
    config = [sources: [%{key: "qonto-main", provider: :qonto, name: "Qonto Main"}]]

    assert {:ok, %{key: "qonto-main", provider: :qonto, name: "Qonto Main"}} =
             Config.fetch_source("qonto-main", config)

    assert {:error, :source_not_configured} = Config.fetch_source("missing", config)
  end

  test "returns configured finance defaults" do
    config = [
      report_currency: " usd ",
      runway_window_days: 120,
      initial_lookback_days: 400,
      sync_overlap_minutes: 7
    ]

    assert Config.report_currency(config) == "USD"
    assert Config.runway_window_days(config) == 120
    assert Config.initial_lookback_days(config) == 400
    assert Config.sync_overlap_seconds(config) == 420
  end

  test "falls back to built-in defaults for missing or invalid values" do
    config = [
      report_currency: "   ",
      runway_window_days: -1,
      initial_lookback_days: 0,
      sync_overlap_minutes: nil
    ]

    assert Config.report_currency(config) == "EUR"
    assert Config.runway_window_days(config) == 180
    assert Config.initial_lookback_days(config) == 365
    assert Config.sync_overlap_seconds(config) == 300
  end

  test "normalizes internal entity names" do
    config = [internal_entity_names: ["  Tuist GmbH ", "Tuist Inc.", "", nil]]

    assert Config.normalized_internal_entity_names(config) == ["tuist gmbh", "tuist inc."]
  end

  test "matches intercompany counterparties by prefix" do
    names = Config.normalized_internal_entity_names(internal_entity_names: ["Tuist GmbH", "Tuist Inc."])

    assert Config.internal_counterparty?("Tuist GmbH", names)
    # Bank-appended address must still match the configured entity.
    assert Config.internal_counterparty?("Tuist Inc.\n, 1111B S Governors Ave", names)
    assert Config.internal_counterparty?("  tuist inc.  ", names)

    refute Config.internal_counterparty?("Acme Ltd", names)
    refute Config.internal_counterparty?(nil, names)
    refute Config.internal_counterparty?("Tuist GmbH", [])
  end
end
