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

  test "names the repository targets a run took from the cache without counters", %{
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
    target.(name: "Kit", binary_cache_hit: :miss)

    assert Xcode.uninstrumented_targets(project.id, [run_id]) == %{run_id => ["Core"]}
  end

  test "a run that took nothing from the cache without counters has no entry", %{project: project} do
    run_id = UUIDv7.generate()
    event = CommandEventsFixtures.command_event_fixture(project_id: project.id, name: "test", test_run_id: run_id)
    XcodeFixtures.xcode_target_fixture(command_event_id: event.id, name: "Core", binary_cache_hit: :miss)

    assert Xcode.uninstrumented_targets(project.id, [run_id]) == %{}
  end
end
