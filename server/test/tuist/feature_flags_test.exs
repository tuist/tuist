defmodule Tuist.FeatureFlagsTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Accounts.Account
  alias Tuist.Environment
  alias Tuist.FeatureFlags

  setup :set_mimic_from_context

  describe "kura_stable_hostname_enabled?/1" do
    test "staging and production require an explicit account or global flag" do
      account = %Account{id: 42, name: "tuist"}

      for env <- [:stag, :prod, :dev, :test] do
        stub(Environment, :env, fn -> env end)
        expect(FunWithFlags, :enabled?, fn :kura_stable_hostname, [for: ^account] -> false end)
        refute FeatureFlags.kura_stable_hostname_enabled?(account)

        expect(FunWithFlags, :enabled?, fn :kura_stable_hostname, [for: ^account] -> true end)
        assert FeatureFlags.kura_stable_hostname_enabled?(account)
      end
    end

    test "canary enables stable hostnames automatically" do
      reject(FunWithFlags, :enabled?, 2)
      stub(Environment, :env, fn -> :can end)
      assert FeatureFlags.kura_stable_hostname_enabled?(%Account{id: 42, name: "tuist"})
    end

    test "global rollout enables accounts while preserving explicit account opt-outs" do
      enabled = %Account{id: 42, name: "enabled"}
      opted_out = %Account{id: 43, name: "opted-out"}

      flag = %FunWithFlags.Flag{
        name: :kura_stable_hostname,
        gates: [
          %FunWithFlags.Gate{type: :boolean, enabled: true},
          %FunWithFlags.Gate{type: :actor, for: "account:43", enabled: false}
        ]
      }

      stub(Environment, :env, fn -> :prod end)

      stub(FunWithFlags, :enabled?, fn :kura_stable_hostname, [for: account] ->
        FunWithFlags.Flag.enabled?(flag, for: account)
      end)

      assert FeatureFlags.kura_stable_hostname_enabled?(enabled)
      refute FeatureFlags.kura_stable_hostname_enabled?(opted_out)
    end
  end

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

  describe "runner_cache_volumes_per_repository_enabled?/0" do
    test "requires the flag in canary and production" do
      for env <- [:can, :prod] do
        stub(Environment, :env, fn -> env end)
        expect(FunWithFlags, :enabled?, fn :runner_cache_volumes_per_repository -> false end)

        refute FeatureFlags.runner_cache_volumes_per_repository_enabled?()
      end
    end

    test "is on once the flag is enabled" do
      stub(Environment, :env, fn -> :prod end)
      expect(FunWithFlags, :enabled?, fn :runner_cache_volumes_per_repository -> true end)

      assert FeatureFlags.runner_cache_volumes_per_repository_enabled?()
    end

    test "is on elsewhere without consulting the flag" do
      stub(Environment, :env, fn -> :stag end)
      reject(FunWithFlags, :enabled?, 1)

      assert FeatureFlags.runner_cache_volumes_per_repository_enabled?()
    end
  end

  describe "turnstile_enabled?/0" do
    test "is on when the env toggle is set and the kill switch is off" do
      stub(Environment, :turnstile_required?, fn -> true end)
      expect(FunWithFlags, :enabled?, fn :turnstile_kill_switch -> false end)

      assert FeatureFlags.turnstile_enabled?()
    end

    test "is off when the kill switch is on, regardless of the env toggle" do
      stub(Environment, :turnstile_required?, fn -> true end)
      expect(FunWithFlags, :enabled?, fn :turnstile_kill_switch -> true end)

      refute FeatureFlags.turnstile_enabled?()
    end

    test "is off when the env toggle is off, without consulting the kill switch" do
      stub(Environment, :turnstile_required?, fn -> false end)
      reject(FunWithFlags, :enabled?, 1)

      refute FeatureFlags.turnstile_enabled?()
    end
  end
end
