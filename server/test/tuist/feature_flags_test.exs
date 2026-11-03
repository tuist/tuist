defmodule Tuist.FeatureFlagsTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Accounts.Account
  alias Tuist.Environment
  alias Tuist.FeatureFlags
  alias Tuist.Projects.Project

  setup :set_mimic_from_context

  describe "runner_docker_cache_enabled?/1" do
    test "canary qualification does not depend on a database flag" do
      stub(Environment, :env, fn -> :can end)
      reject(FunWithFlags, :enabled?, 2)

      assert FeatureFlags.runner_docker_cache_enabled?(%Account{id: 42})
    end

    test "production still requires the account or global rollout flag" do
      account = %Account{id: 42}
      stub(Environment, :env, fn -> :prod end)

      for enabled <- [false, true] do
        expect(FunWithFlags, :enabled?, fn :runner_docker_cache, [for: ^account] -> enabled end)
        assert FeatureFlags.runner_docker_cache_enabled?(account) == enabled
      end
    end

    test "development, test and staging retain their enabled default" do
      reject(FunWithFlags, :enabled?, 2)

      for env <- [:dev, :test, :stag] do
        stub(Environment, :env, fn -> env end)
        assert FeatureFlags.runner_docker_cache_enabled?(%Account{id: 42})
      end
    end

    test "production account opt-outs override a global rollout" do
      account = %Account{id: 42}

      flag = %FunWithFlags.Flag{
        name: :runner_docker_cache,
        gates: [
          %FunWithFlags.Gate{type: :boolean, enabled: true},
          %FunWithFlags.Gate{type: :actor, for: "account:42", enabled: false}
        ]
      }

      stub(Environment, :env, fn -> :prod end)

      expect(FunWithFlags, :enabled?, fn :runner_docker_cache, [for: ^account] ->
        FunWithFlags.Flag.enabled?(flag, for: account)
      end)

      refute FeatureFlags.runner_docker_cache_enabled?(account)
    end
  end

  describe "immutable_shard_reports_enabled?/1" do
    test "coverage-enabled accounts cannot create immutable plans" do
      account = %Account{id: 42, name: "tuist"}
      stub(Environment, :env, fn -> :prod end)

      for coverage? <- [true, false] do
        stub(FunWithFlags, :enabled?, fn
          :immutable_shard_reports, [for: ^account] -> true
          :xcode_coverage, [for: ^account] -> coverage?
        end)

        assert FeatureFlags.immutable_shard_reports_enabled?(account) == not coverage?
      end
    end

    test "environments with coverage enabled by default remain on legacy plans" do
      stub(Environment, :env, fn -> :stag end)
      expect(FunWithFlags, :enabled?, fn :immutable_shard_reports, _ -> true end)
      refute FeatureFlags.immutable_shard_reports_enabled?(%Account{id: 42, name: "tuist"})
    end

    test "Mix projects, which always have coverage, remain on legacy plans" do
      account = %Account{id: 42, name: "tuist"}
      stub(Environment, :env, fn -> :prod end)

      stub(FunWithFlags, :enabled?, fn
        :immutable_shard_reports, [for: ^account] -> true
        :xcode_coverage, [for: ^account] -> false
      end)

      refute FeatureFlags.immutable_shard_reports_enabled?(%Project{id: 1, account: account, build_system: :mix})
      assert FeatureFlags.immutable_shard_reports_enabled?(%Project{id: 2, account: account, build_system: :xcode})
    end
  end

  describe "coverage_enabled?/2" do
    test "Mix projects have coverage in every account; other projects follow the account's flag" do
      account = %Account{id: 42, name: "tuist"}
      stub(Environment, :env, fn -> :prod end)

      for flag? <- [true, false], build_system <- [:mix, :xcode, :gradle, :bazel] do
        stub(FunWithFlags, :enabled?, fn :xcode_coverage, [for: ^account] -> flag? end)

        assert FeatureFlags.coverage_enabled?(account, %Project{build_system: build_system}) ==
                 (flag? or build_system == :mix)
      end
    end
  end

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

  describe "runner_site_enabled?/1" do
    test "is on for every account in staging and canary" do
      for env <- [:stag, :can] do
        stub(Environment, :env, fn -> env end)
        reject(FunWithFlags, :enabled?, 2)

        assert FeatureFlags.runner_site_enabled?(%Account{id: 42, name: "tuist"})
      end
    end

    test "uses the flag in production and development" do
      account = %Account{id: 42, name: "tuist"}

      for env <- [:prod, :dev] do
        stub(Environment, :env, fn -> env end)
        expect(FunWithFlags, :enabled?, fn :runner_site, [for: ^account] -> false end)

        refute FeatureFlags.runner_site_enabled?(account)
      end
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
