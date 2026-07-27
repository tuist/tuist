defmodule Tuist.FeatureFlagsTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Accounts.Account
  alias Tuist.Environment
  alias Tuist.FeatureFlags

  setup :set_mimic_from_context

  test "uses the configured runner account allowlist" do
    stub(Environment, :runner_enabled_account_names, fn -> ["tuist"] end)
    reject(FunWithFlags, :enabled?, 2)

    assert FeatureFlags.runners_enabled?(%Account{name: "tuist"})
    refute FeatureFlags.runners_enabled?(%Account{name: "other"})
  end

  test "fails closed in canary without a configured runner account allowlist" do
    stub(Environment, :runner_enabled_account_names, fn -> nil end)
    stub(Environment, :env, fn -> :can end)
    reject(FunWithFlags, :enabled?, 2)

    refute FeatureFlags.runners_enabled?(%Account{name: "tuist"})
  end

  test "uses the runner feature flag in production without an allowlist" do
    account = %Account{id: 42, name: "tuist"}

    stub(Environment, :runner_enabled_account_names, fn -> nil end)
    stub(Environment, :env, fn -> :prod end)

    expect(FunWithFlags, :enabled?, fn :runners, [for: ^account] -> true end)

    assert FeatureFlags.runners_enabled?(account)
  end
end
