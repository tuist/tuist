defmodule Tuist.FeatureFlagsTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Accounts.Account
  alias Tuist.Environment
  alias Tuist.FeatureFlags

  setup :set_mimic_from_context

  test "uses the runner feature flag in canary" do
    account = %Account{id: 42, name: "tuist"}

    stub(Environment, :env, fn -> :can end)

    expect(FunWithFlags, :enabled?, fn :runners, [for: ^account] -> true end)

    assert FeatureFlags.runners_enabled?(account)
  end

  test "uses the runner feature flag in production" do
    account = %Account{id: 42, name: "tuist"}

    stub(Environment, :env, fn -> :prod end)

    expect(FunWithFlags, :enabled?, fn :runners, [for: ^account] -> true end)

    assert FeatureFlags.runners_enabled?(account)
  end

  test "uses a runner feature flag snapshot in canary" do
    account = %Account{id: 42, name: "tuist"}
    other = %Account{id: 43, name: "other"}

    flag = %FunWithFlags.Flag{
      name: :runners,
      gates: [%FunWithFlags.Gate{type: :actor, for: "account:#{account.id}", enabled: true}]
    }

    stub(Environment, :env, fn -> :can end)

    assert FeatureFlags.runners_enabled?(account, flag)
    refute FeatureFlags.runners_enabled?(other, flag)
  end

  test "defaults to enabled outside canary and production" do
    stub(Environment, :env, fn -> :dev end)
    reject(FunWithFlags, :enabled?, 2)

    assert FeatureFlags.runners_enabled?(%Account{name: "tuist"})
  end
end
