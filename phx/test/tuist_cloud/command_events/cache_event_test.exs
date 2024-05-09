defmodule TuistCloud.InvitationTest do
  alias TuistCloud.CommandEvents.CacheEvent
  use TuistCloud.DataCase
  use Mimic

  describe "create_changeset" do
    test "ensures the hash is present" do
      # Given
      cache_event = %{
        project_id: 1,
        name: "Test",
        event_type: "download",
        size: 100
      }

      # When
      got = CacheEvent.create_changeset(%CacheEvent{}, cache_event)

      # Then
      assert "can't be blank" in errors_on(got).hash
    end
  end
end
