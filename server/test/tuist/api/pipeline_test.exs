defmodule Tuist.API.PipelineTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.API.Pipeline
  alias Tuist.CacheActionItems
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    project = ProjectsFixtures.project_fixture()
    %{project: project}
  end

  test "create cache action item", %{project: project} do
    # Given
    first_cache_action_item = %{
      project_id: project.id,
      hash: UUIDv7.generate(),
      inserted_at: DateTime.utc_now(:second),
      updated_at: DateTime.utc_now(:second)
    }

    second_cache_action_item = %{
      project_id: project.id,
      hash: UUIDv7.generate(),
      inserted_at: DateTime.utc_now(:second),
      updated_at: DateTime.utc_now(:second)
    }

    # When
    first_ref =
      Broadway.test_message(Pipeline, {:create_cache_action_item, first_cache_action_item},
        metadata: %{ecto_sandbox: self()}
      )

    second_ref =
      Broadway.test_message(Pipeline, {:create_cache_action_item, second_cache_action_item},
        metadata: %{ecto_sandbox: self()}
      )

    # Then
    assert_receive {:ack, ^first_ref,
                    [
                      %Broadway.Message{
                        data: {:create_cache_action_item, ^first_cache_action_item}
                      }
                    ], []}

    assert_receive {:ack, ^second_ref,
                    [
                      %Broadway.Message{
                        data: {:create_cache_action_item, ^second_cache_action_item}
                      }
                    ], []}

    assert CacheActionItems.get_cache_action_item(%{
             project: project,
             hash: first_cache_action_item.hash
           })

    assert CacheActionItems.get_cache_action_item(%{
             project: project,
             hash: second_cache_action_item.hash
           })
  end
end
