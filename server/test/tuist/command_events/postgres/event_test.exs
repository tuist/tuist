defmodule Tuist.CommandEvents.Postgres.EventTest do
  use TuistTestSupport.Cases.DataCase
  use Mimic

  alias Tuist.CommandEvents.Postgres.Event

  describe "create_changeset" do
    test "ensures status is either success or failure" do
      # When
      got = Event.create_changeset(%Event{}, command_event(status: :invalid))

      # Then
      assert got.valid? == false
      assert "is invalid" in errors_on(got).status
    end

    test "changeset is valid if status is success" do
      # When
      got = Event.create_changeset(%Event{}, command_event(status: :success))

      # Then
      assert got.valid? == true
    end

    test "changeset is valid if status is failure" do
      # When
      got = Event.create_changeset(%Event{}, command_event(status: :failure))

      # Then
      assert got.valid? == true
    end

    test "changeset is valid if a user_id is provided" do
      # When
      got = Event.create_changeset(%Event{}, command_event(user_id: 2))

      # Then
      assert got.valid? == true
    end

    test "changeset is not valid if a user_id is not provided" do
      # When
      got = Event.create_changeset(%Event{}, command_event(user_id: nil))

      # Then
      assert got.valid? == false
      assert "can't be blank" in errors_on(got).user_id
    end

    test "changeset is valid if a user_id is not provided and is ci" do
      # When
      got = Event.create_changeset(%Event{}, command_event(user_id: nil, is_ci: true))

      # Then
      assert got.valid? == true
    end

    test "populates the remote_test_target_hits_count value automatically" do
      # When
      got =
        Event.create_changeset(
          %Event{},
          command_event(
            remote_test_target_hits: ["foo", "bar"],
            remote_cache_target_hits: ["test"]
          )
        )

      assert get_change(got, :remote_cache_target_hits_count) == 1
      assert get_change(got, :remote_test_target_hits_count) == 2
    end
  end

  defp command_event(attrs) do
    %{
      name: "generate",
      subcommand: "",
      command_arguments: "",
      duration: 100,
      tuist_version: "4.1.0",
      swift_version: "5.2",
      macos_version: "10.15",
      project_id: 1,
      cacheable_targets: "",
      local_cache_target_hits: "",
      remote_test_target_hits: Keyword.get(attrs, :remote_test_target_hits, []),
      remote_cache_target_hits: Keyword.get(attrs, :remote_cache_target_hits, []),
      is_ci: Keyword.get(attrs, :is_ci, false),
      user_id: Keyword.get(attrs, :user_id, 1),
      client_id: "client-id",
      status: Keyword.get(attrs, :status, :success),
      error_message: nil,
      ran_at: ~U[2022-02-28 15:54:06Z],
      build_run_id: Keyword.get(attrs, :build_run_id)
    }
  end
end
