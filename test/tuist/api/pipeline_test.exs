defmodule Tuist.API.PipelineTest do
  alias Tuist.API.Pipeline
  use TuistTestSupport.Cases.DataCase, async: false
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias Tuist.CommandEvents

  setup do
    project = ProjectsFixtures.project_fixture()
    %{project: project}
  end

  test "cache events", %{project: project} do
    # Given
    first_event = %{
      project_id: project.id,
      name: UUIDv7.generate(),
      event_type: :upload,
      size: 1024,
      hash: UUIDv7.generate(),
      created_at: ~N[2023-12-25 14:30:00],
      updated_at: ~N[2023-12-25 14:30:00]
    }

    second_event = %{
      project_id: project.id,
      name: UUIDv7.generate(),
      event_type: :download,
      size: 1024,
      hash: UUIDv7.generate(),
      created_at: ~N[2023-12-25 14:30:01],
      updated_at: ~N[2023-12-25 14:30:01]
    }

    # When
    first_ref =
      Broadway.test_message(Pipeline, {:cache_event, first_event},
        metadata: %{ecto_sandbox: self()}
      )

    second_ref =
      Broadway.test_message(Pipeline, {:cache_event, second_event})

    # Then
    assert_receive {:ack, ^first_ref, [%Broadway.Message{data: {:cache_event, ^first_event}}], []}

    got_first_cache_event =
      CommandEvents.get_cache_event(%{
        hash: first_event[:hash],
        event_type: first_event[:event_type]
      })

    assert got_first_cache_event.size == 1024

    assert_receive {:ack, ^second_ref, [%Broadway.Message{data: {:cache_event, ^second_event}}],
                    []}

    got_second_event =
      CommandEvents.get_cache_event(%{
        hash: second_event[:hash],
        event_type: second_event[:event_type]
      })

    assert got_second_event.size == 1024
  end
end
