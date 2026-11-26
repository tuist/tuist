defmodule Tuist.FeatureFlagsTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Accounts.Account
  alias Tuist.Environment
  alias Tuist.FeatureFlags
  alias Tuist.Projects.Project

  setup :set_mimic_from_context

  describe "organization_luft_enabled?/1" do
    test "requires the account flag in every environment, independently of personal AI" do
      account = %Account{id: 42}

      for env <- [:dev, :test, :stag, :can, :prod], enabled <- [false, true] do
        stub(Environment, :env, fn -> env end)
        expect(FunWithFlags, :enabled?, fn :luft, [for: ^account] -> enabled end)
        assert FeatureFlags.organization_luft_enabled?(account) == enabled
      end
    end
  end

  describe "sandbox flags" do
    test "canary and production open each platform with :sandboxes or its own flag, and the API with any of them" do
      account = %Account{id: 42}

      for env <- [:can, :prod], on <- [[], [:sandboxes], [:linux_sandboxes], [:macos_sandboxes]] do
        stub(Environment, :env, fn -> env end)
        stub(FunWithFlags, :enabled?, fn flag, [for: ^account] -> flag in on end)

        assert FeatureFlags.sandbox_platform_enabled?(account, :linux) ==
                 (:sandboxes in on or :linux_sandboxes in on)

        assert FeatureFlags.sandbox_platform_enabled?(account, :darwin) ==
                 (:sandboxes in on or :macos_sandboxes in on)

        assert FeatureFlags.sandboxes_enabled?(account) == (on != [])
      end
    end

    test "development, test and staging enable every platform without a flag" do
      reject(FunWithFlags, :enabled?, 2)

      for env <- [:dev, :test, :stag], platform <- [:linux, :darwin] do
        stub(Environment, :env, fn -> env end)
        assert FeatureFlags.sandbox_platform_enabled?(%Account{id: 42}, platform)
        assert FeatureFlags.sandboxes_enabled?(%Account{id: 42})
      end
    end
  end

  describe "pulse_enabled?/1" do
    test "requires explicit account enrollment in every environment" do
      account = %Account{id: 42}

      for env <- [:dev, :test, :stag, :can, :prod], enabled <- [false, true] do
        stub(Environment, :env, fn -> env end)
        expect(FunWithFlags, :enabled?, fn :pulse, [for: ^account] -> enabled end)
        assert FeatureFlags.pulse_enabled?(account) == enabled
      end
    end
  end

  describe "app_flags/1" do
    test "lists code only for users with the flag in production" do
      user = %Tuist.Accounts.User{id: 42}
      stub(Environment, :env, fn -> :prod end)

      for {enabled, flags} <- [{false, []}, {true, ["luft"]}] do
        expect(FunWithFlags, :enabled?, fn :luft, [for: ^user] -> enabled end)
        assert FeatureFlags.app_flags(user) == flags
      end
    end
  end

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
    test "is off for every project and account, even when the account has the toggle" do
      account = %Account{id: 42, name: "tuist"}
      reject(FunWithFlags, :enabled?, 2)

      for env <- [:dev, :stag, :can, :prod] do
        stub(Environment, :env, fn -> env end)
        refute FeatureFlags.immutable_shard_reports_enabled?(account)

        for build_system <- [:xcode, :mix, :cargo, :gradle, :bazel, :once] do
          refute FeatureFlags.immutable_shard_reports_enabled?(%Project{
                   id: 1,
                   account: account,
                   build_system: build_system
                 })
        end
      end
    end
  end

  describe "test_impact_analysis_enabled?/2" do
    test "canary and production require the account flag" do
      account = %Account{id: 42, name: "tuist"}

      for env <- [:can, :prod], flag? <- [true, false], build_system <- [:xcode, :once] do
        stub(Environment, :env, fn -> env end)
        stub(FunWithFlags, :enabled?, fn :test_impact_analysis, [for: ^account] -> flag? end)

        assert FeatureFlags.test_impact_analysis_enabled?(account, %Project{build_system: build_system}) == flag?
      end
    end

    test "other environments enable it for projects with coverage only" do
      account = %Account{id: 42, name: "tuist"}
      stub(Environment, :env, fn -> :stag end)

      assert FeatureFlags.test_impact_analysis_enabled?(account, %Project{build_system: :xcode})
      refute FeatureFlags.test_impact_analysis_enabled?(account, %Project{build_system: :bazel})
    end

    test "a project without coverage never gets it, whatever the account flag" do
      account = %Account{id: 42, name: "tuist"}
      stub(Environment, :env, fn -> :prod end)
      stub(FunWithFlags, :enabled?, fn :test_impact_analysis, [for: ^account] -> true end)

      refute FeatureFlags.test_impact_analysis_enabled?(account, %Project{build_system: :bazel})
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
