defmodule Tuist.Builds.StepCollectionTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Builds
  alias Tuist.Builds.Steps
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  test "builds without recorded steps still ingest normally" do
    {:ok, build} = RunsFixtures.build_fixture()
    assert %{events: [], total_count: 0} = Builds.build_timeline(build.id)
    assert {:ok, %{availability: "unavailable", steps: []}} = Steps.list(build)
    assert {:error, :not_found} = Steps.get(build.id, "1")
    assert {:ok, _} = Builds.get_build(build.id)
  end

  test "collects streamed steps and logs by default without consulting feature flags" do
    owner = AccountsFixtures.user_fixture(preload: [:account])
    uploader = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: owner.account.id)

    reject(FunWithFlags, :enabled?, 2)

    steps =
      Stream.map([1], fn id ->
        %{event_id: id, title: "Compile", start_ms: 0.0, duration_ms: 1.0, status: "success", log: "Recorded output"}
      end)

    {:ok, build} =
      RunsFixtures.build_fixture(
        project_id: project.id,
        user_id: uploader.account.id,
        build_steps: steps
      )

    assert %{total_count: 1} = Builds.build_timeline(build.id)
    assert {:ok, %{availability: "available", steps: [_]}} = Steps.list(build)
    assert {:ok, %{log: "Recorded output"}} = Steps.get(build.id, "1")
  end
end
