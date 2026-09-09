defmodule Tuist.Builds.StepCollectionTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Builds
  alias Tuist.Builds.Steps
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  test "disabled collection never consumes the step stream or retains logs" do
    expect(FunWithFlags, :enabled?, fn :xcode_build_steps, [for: _account] -> false end)
    steps = Stream.map([1], fn _ -> flunk("disabled collection must not consume raw step logs") end)
    {:ok, build} = RunsFixtures.build_fixture(build_steps: steps)
    assert %{events: [], total_count: 0} = Builds.build_timeline(build.id)
    assert {:ok, %{availability: "unavailable", steps: []}} = Steps.list(build)
    assert {:error, :not_found} = Steps.get(build.id, "1")
    assert {:ok, _} = Builds.get_build(build.id)
  end

  test "collection is checked against the owning account, not the uploader" do
    owner = AccountsFixtures.user_fixture(preload: [:account])
    uploader = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: owner.account.id)

    expect(FunWithFlags, :enabled?, fn :xcode_build_steps, [for: account] ->
      assert account.id == owner.account.id
      refute account.id == uploader.account.id
      true
    end)

    {:ok, build} =
      RunsFixtures.build_fixture(
        project_id: project.id,
        user_id: uploader.account.id,
        build_steps: [
          %{event_id: 1, title: "Compile", start_ms: 0.0, duration_ms: 1.0, status: "success", log: "Recorded output"}
        ]
      )

    assert {:ok, %{log: "Recorded output"}} = Steps.get(build.id, "1")
  end
end
