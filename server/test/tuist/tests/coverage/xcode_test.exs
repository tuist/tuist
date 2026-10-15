defmodule Tuist.Tests.Coverage.XcodeTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Tests.Coverage.Xcode
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.XcodeFixtures

  setup do
    account = AccountsFixtures.user_fixture(preload: [:account]).account
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    %{project: project}
  end

  test "names the targets a run took from the cache without counters, and the test targets linking them", %{
    project: project
  } do
    run_id = UUIDv7.generate()
    event = CommandEventsFixtures.command_event_fixture(project_id: project.id, name: "test", test_run_id: run_id)
    target = fn opts -> XcodeFixtures.xcode_target_fixture([command_event_id: event.id] ++ opts) end

    target.(name: "Core", binary_cache_hit: :local)
    target.(name: "Counted", binary_cache_hit: :remote, binary_cache_instrumented: true)
    target.(name: "Alamofire", binary_cache_hit: :remote, external_hash: "alamofire-revision")
    target.(name: "KitResources", product: "bundle", binary_cache_hit: :local)
    target.(name: "KitMacros", product: "macro", binary_cache_hit: :local)
    target.(name: "Kit", binary_cache_hit: :miss, dependencies: ["Core", "Counted", "KitResources", "KitMacros"])
    target.(name: "KitTests", product: "unit_tests", dependencies: ["Kit"])
    target.(name: "CountedTests", product: "unit_tests", dependencies: ["Counted", "Alamofire", "KitResources"])
    target.(name: "App", product: "app", dependencies: ["Kit"])

    assert Xcode.uninstrumented_targets(project.id, [run_id]) == %{run_id => ["Core"]}
    assert Xcode.uninstrumented_test_targets(project.id, [run_id]) == MapSet.new([{run_id, "KitTests"}])
  end

  test "a run that took nothing from the cache without counters has no entry", %{project: project} do
    run_id = UUIDv7.generate()
    event = CommandEventsFixtures.command_event_fixture(project_id: project.id, name: "test", test_run_id: run_id)
    XcodeFixtures.xcode_target_fixture(command_event_id: event.id, name: "Core", binary_cache_hit: :miss)

    assert Xcode.uninstrumented_targets(project.id, [run_id]) == %{}
    assert Xcode.uninstrumented_test_targets(project.id, [run_id]) == MapSet.new()
  end
end
