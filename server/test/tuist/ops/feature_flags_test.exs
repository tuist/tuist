defmodule Tuist.Ops.FeatureFlagsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias FunWithFlags.Flag
  alias FunWithFlags.Gate
  alias FunWithFlags.Store.Persistent.Ecto.Record
  alias Tuist.Environment
  alias Tuist.FeatureFlags, as: Evaluation
  alias Tuist.Observability
  alias Tuist.Ops.FeatureFlags
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.KuraFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.TelemetryCapture

  setup do
    stub(Environment, :env, fn -> :prod end)
    :ok
  end

  test "account inspection respects actor exclusions and never enumerates projects" do
    excluded = AccountsFixtures.user_fixture().account
    included = AccountsFixtures.user_fixture().account
    gate(:runners, :boolean, nil, true)
    gate(:runners, :actor, "account:#{excluded.id}", false)
    gate(:runner_site_cache, :actor, "account:#{included.id}", true)
    reject(FunWithFlags, :enabled?, 1)
    reject(FunWithFlags, :enabled?, 2)

    assert {:ok, result} = FeatureFlags.evaluate(%{"account_id" => excluded.id})
    assert result.resource == %{account_id: excluded.id, project_id: nil}
    assert result.environment == "prod"
    assert length(result.evaluations) == 16
    refute Enum.any?(result.evaluations, &(&1.actor_type == "project"))
    refute enabled?(result, "runners")
    refute enabled?(result, "runner_site_cache")

    assert {:ok, result} = FeatureFlags.evaluate(%{"account_id" => included.id})
    assert enabled?(result, "runners")
    assert enabled?(result, "runner_site_cache")
  end

  test "the persisted batch excludes other actors and flags outside the catalog" do
    account = AccountsFixtures.user_fixture().account
    gate(:runners, :boolean, nil, true)
    gate(:runner_site_cache, :actor, "account:#{account.id}", true)
    gate(:outside_the_operator_catalog, :boolean, nil, true)

    for id <- 1..50 do
      gate(:runners, :actor, "account:unrelated-#{id}", true)
      gate(:build_entities, :actor, "project:unrelated-#{id}", true)
    end

    ref = TelemetryCapture.attach_event_handlers([[:tuist, :repo, :query]])
    assert {:ok, result} = FeatureFlags.evaluate(%{"account_id" => account.id})
    assert enabled?(result, "runners")
    assert enabled?(result, "runner_site_cache")

    assert_receive {[:tuist, :repo, :query], ^ref, _, %{source: "feature_flags", result: {:ok, %{num_rows: 2}}}}
  end

  test "project inspection resolves its owning account and honors the global inventory kill switch" do
    project = ProjectsFixtures.project_fixture()
    gate(:runner_site_cache, :actor, "account:#{project.account_id}", true)
    gate(:build_entities, :actor, "project:#{project.id}", true)
    reject(FunWithFlags, :enabled?, 1)
    reject(FunWithFlags, :enabled?, 2)
    previous = Observability.snapshot().context

    assert {:ok, result} = FeatureFlags.evaluate(%{"project_id" => project.id})
    assert result.resource == %{account_id: project.account_id, project_id: project.id}
    assert length(result.evaluations) == 17
    assert enabled?(result, "build_entities")
    assert enabled?(result, "runner_site_cache")
    assert Enum.find(result.evaluations, &(&1.name == "runner_site_cache")).actor_id == project.account_id
    assert Observability.snapshot().context == previous

    gate(:build_entities_kill_switch, :boolean, nil, true)
    assert {:ok, result} = FeatureFlags.evaluate(%{"project_id" => project.id})
    refute enabled?(result, "build_entities")
    assert enabled?(result, "build_entities_kill_switch")
  end

  test "coverage dependency is evaluated from the same persisted batch" do
    account = AccountsFixtures.user_fixture().account
    gate(:immutable_shard_reports, :actor, "account:#{account.id}", true)
    coverage = gate(:xcode_coverage, :actor, "account:#{account.id}", true)

    assert {:ok, result} = FeatureFlags.evaluate(%{"account_id" => account.id})
    assert enabled?(result, "xcode_coverage")
    refute enabled?(result, "immutable_shard_reports")

    Repo.delete!(coverage)
    assert {:ok, result} = FeatureFlags.evaluate(%{"account_id" => account.id})
    refute enabled?(result, "xcode_coverage")
    assert enabled?(result, "immutable_shard_reports")
  end

  test "environment defaults are effective decisions, not empty-rule defaults" do
    account = AccountsFixtures.user_fixture().account
    gate(:immutable_shard_reports, :actor, "account:#{account.id}", true)

    for {env, runners, coverage, site, stable} <- [
          {:prod, false, false, false, false},
          {:can, false, false, true, true},
          {:stag, true, true, true, false},
          {:dev, true, true, false, false}
        ] do
      stub(Environment, :env, fn -> env end)
      assert {:ok, result} = FeatureFlags.evaluate(%{"account_id" => account.id})
      assert result.environment == Atom.to_string(env)
      assert enabled?(result, "runners") == runners
      assert enabled?(result, "xcode_coverage") == coverage
      assert enabled?(result, "runner_site") == site
      assert enabled?(result, "kura_stable_hostname") == stable
      assert enabled?(result, "immutable_shard_reports") == not coverage
    end
  end

  test "inverted global helpers identify their effective feature and direct pause gates keep their polarity" do
    account = AccountsFixtures.user_fixture().account
    stub(Environment, :turnstile_required?, fn -> true end)
    stub(Environment, :public_page_challenge_required?, fn -> true end)

    pairs = [
      {"kura_rollout_orchestration_kill_switch", "kura_rollout_orchestration"},
      {"turnstile_kill_switch", "turnstile"},
      {"public_page_challenge_kill_switch", "public_page_challenge"}
    ]

    assert {:ok, result} = FeatureFlags.evaluate(%{"account_id" => account.id})

    for {name, feature} <- pairs do
      assert %{feature: ^feature, enabled: true, actor_type: "global", actor_id: nil} =
               Enum.find(result.evaluations, &(&1.name == name))

      gate(String.to_existing_atom(name), :boolean, nil, true)
    end

    gate(:runner_pod_reconciliation_paused, :boolean, nil, true)
    gate(:qa_billing_enabled, :actor, "account:#{account.id}", true)
    assert {:ok, result} = FeatureFlags.evaluate(%{"account_id" => account.id})
    assert Enum.all?(pairs, fn {name, _} -> not enabled?(result, name) end)
    assert enabled?(result, "runner_pod_reconciliation_paused")
    assert enabled?(result, "qa_billing_enabled")
  end

  test "percentage gates use the same stable actor evaluation with explicit exclusions taking precedence" do
    accounts = Enum.map(1..4, fn _ -> AccountsFixtures.user_fixture().account end)
    [excluded | _] = accounts
    gate(:runners, :percentage_of_actors, 0.5, true)
    gate(:runners, :actor, "account:#{excluded.id}", false)

    flag = %Flag{
      name: :runners,
      gates: [
        %Gate{type: :percentage_of_actors, for: 0.5, enabled: true},
        %Gate{type: :actor, for: "account:#{excluded.id}", enabled: false}
      ]
    }

    for account <- accounts do
      expected = Flag.enabled?(flag, for: account)
      assert {:ok, result} = FeatureFlags.evaluate(%{"account_id" => account.id})
      assert enabled?(result, "runners") == expected
      assert {:ok, ^result} = FeatureFlags.evaluate(%{"account_id" => account.id})
    end
  end

  test "rename eligibility uses actual Kura state as well as its rollout gate" do
    account = AccountsFixtures.user_fixture().account
    assert {:ok, result} = FeatureFlags.evaluate(%{"account_id" => account.id})
    assert enabled?(result, "kura_account_rename")

    KuraFixtures.active_server_fixture(account)
    assert {:ok, result} = FeatureFlags.evaluate(%{"account_id" => account.id})
    refute enabled?(result, "kura_account_rename")
    gate(:kura_account_rename, :actor, "account:#{account.id}", true)
    assert {:ok, result} = FeatureFlags.evaluate(%{"account_id" => account.id})
    assert enabled?(result, "kura_account_rename")
  end

  test "cold and repeated evaluations use at most four queries without cached flag reads" do
    account = AccountsFixtures.user_fixture().account
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    reject(FunWithFlags, :enabled?, 1)
    reject(FunWithFlags, :enabled?, 2)
    ref = TelemetryCapture.attach_event_handlers([[:tuist, :repo, :query]])

    for target <- [%{"account_id" => account.id}, %{"project_id" => project.id}], _ <- 1..2 do
      assert {:ok, _} = FeatureFlags.evaluate(target)

      # Resource + batched gates + the rename helper's two EXISTS queries.
      for _ <- 1..4 do
        assert_receive {[:tuist, :repo, :query], ^ref, _, %{query: query}}
        assert query =~ "SELECT"
      end

      refute_receive {[:tuist, :repo, :query], ^ref, _, _}
    end
  end

  test "preloaded helpers preserve short-circuit evaluation and the original runner flag overload" do
    account = AccountsFixtures.user_fixture().account
    stub(Environment, :env, fn -> :can end)
    reject(FunWithFlags, :enabled?, 1)
    reject(FunWithFlags, :enabled?, 2)

    assert Evaluation.kura_stable_hostname_enabled?(account, %{})

    refute Evaluation.immutable_shard_reports_enabled?(account, %{
             immutable_shard_reports: Flag.new(:immutable_shard_reports, [])
           })

    refute Evaluation.runners_enabled?(account, Flag.new(:runners, []))
    assert Evaluation.xcode_coverage_enabled?(nil, %{}) == false
  end

  defp enabled?(result, name), do: Enum.find(result.evaluations, &(&1.name == name)).enabled

  defp gate(name, type, target, enabled) do
    name |> Record.build(%Gate{type: type, for: target, enabled: enabled}) |> Repo.insert!()
  end
end
