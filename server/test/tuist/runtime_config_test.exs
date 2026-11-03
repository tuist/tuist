defmodule Tuist.RuntimeConfigTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Environment

  test "insights access takes precedence over the legacy reporting setting" do
    for {insights, legacy, enabled} <- [
          {nil, nil, false},
          {nil, "true", true},
          {nil, "TRUE", false},
          {"true", nil, true},
          {"true", "false", true},
          {"false", "true", false},
          {"", "true", false},
          {"TRUE", "true", false},
          {" true", "true", false},
          {"1", "true", false}
        ] do
      stub(System, :get_env, fn
        "TUIST_NETWORK_TRUSTED_REPORT_PUBLISHING" -> legacy
        name -> Mimic.call_original(System, :get_env, [name])
      end)

      stub(System, :get_env, fn
        "TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS", default -> insights || default
        name, default -> Mimic.call_original(System, :get_env, [name, default])
      end)

      config = Config.Reader.read!(Path.expand("../../config/runtime.exs", __DIR__), env: :test, target: :host)
      configured = config[:tuist][:network_trusted_report_publishing]

      assert configured == enabled
      assert Environment.network_trusted_report_publishing_enabled?(false, configured) == enabled
      refute Environment.network_trusted_report_publishing_enabled?(true, configured)
    end
  end
end
