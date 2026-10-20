defmodule Tuist.Tests.TestCaseStatesAtTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.IngestRepo
  alias Tuist.Tests
  alias Tuist.Tests.TestCaseEvent
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  test "resolves each state column independently at the requested time and scopes it to the project" do
    project = ProjectsFixtures.project_fixture()
    other_project = ProjectsFixtures.project_fixture()
    id = UUIDv7.generate()
    unknown_id = UUIDv7.generate()
    before = ~N[2026-09-04 11:00:00.000000]
    started_at = ~N[2026-09-04 12:00:00.000000]
    after_run = ~N[2026-09-04 13:00:00.000000]

    events = [
      {project.id, "muted", before},
      {project.id, "marked_flaky", started_at},
      {project.id, "unmuted", after_run},
      {other_project.id, "skipped", started_at}
    ]

    IngestRepo.insert_all(
      TestCaseEvent,
      Enum.map(events, fn {project_id, event_type, at} ->
        %{id: UUIDv7.generate(), project_id: project_id, test_case_id: id, event_type: event_type, inserted_at: at}
      end)
    )

    assert Tests.get_test_case_states_at(project.id, [id, unknown_id], started_at) == %{
             id => %{state: "muted", is_flaky: true},
             unknown_id => %{state: "enabled", is_flaky: false}
           }

    assert Tests.get_test_case_states_at(project.id, [id], after_run)[id].state == "enabled"
    assert Tests.get_test_case_states_at(other_project.id, [id], started_at)[id].state == "skipped"
    assert Tests.get_test_case_states_at(project.id, [], started_at) == %{}
  end
end
