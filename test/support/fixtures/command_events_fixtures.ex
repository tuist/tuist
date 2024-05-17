defmodule TuistCloud.CommandEventsFixtures do
  @moduledoc """
  Fixtures for command events.
  """
  alias TuistCloud.CommandEvents
  alias TuistCloud.Time

  def command_event_fixture(attrs \\ []) do
    project_id =
      Keyword.get_lazy(attrs, :project_id, fn ->
        TuistCloud.ProjectsFixtures.project_fixture().id
      end)

    CommandEvents.create_command_event(
      %{
        name: Keyword.get(attrs, :name),
        subcommand: "",
        command_arguments: [],
        duration: Keyword.get(attrs, :duration, 0),
        tuist_version: "4.1.0",
        swift_version: "5.2",
        macos_version: "10.15",
        project_id: project_id,
        cacheable_targets: Keyword.get(attrs, :cacheable_targets, []),
        local_cache_target_hits: Keyword.get(attrs, :local_cache_target_hits, []),
        remote_cache_target_hits: Keyword.get(attrs, :remote_cache_target_hits, []),
        test_targets: Keyword.get(attrs, :test_targets, []),
        local_test_target_hits: Keyword.get(attrs, :local_test_target_hits, []),
        remote_test_target_hits: Keyword.get(attrs, :remote_test_target_hits, []),
        is_ci: false,
        client_id: "client-id",
        status: Keyword.get(attrs, :status, :success),
        error_message: Keyword.get(attrs, :error_message)
      },
      created_at: Keyword.get(attrs, :created_at, Time.utc_now())
    )
  end
end
