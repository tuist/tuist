defmodule Tuist.IngestRepo.Migrations.BackfillTestRunsFromCommandEvents do
  alias Tuist.IngestRepo
  use Ecto.Migration
  import Ecto.Query

  @disable_ddl_transaction true
  @disable_migration_lock true
  @batch_size 10_000
  @throttle_ms 500

  def up do
    throttle_change_in_batches(&page_query/1, &do_change/1)
  end

  def down do
    :ok
  end

  def do_change(batch_of_events) do
    # Create a mapping of command_event_id to test_run_id
    mappings =
      batch_of_events
      |> Enum.map(fn event ->
        test_run_id = Ecto.UUID.generate()

        test_run =
          event
          |> create_test_run_from_event()
          |> Map.put(:id, test_run_id)

        {event.id, test_run_id, test_run}
      end)

    test_runs_data = Enum.map(mappings, fn {_event_id, _test_run_id, test_run} -> test_run end)

      IngestRepo.insert_all("test_runs", test_runs_data,
        on_conflict: :nothing,
        types: %{
          id: :uuid,
          project_id: :i64,
          duration: :i32,
          macos_version: :string,
          xcode_version: :string,
          is_ci: :boolean,
          model_identifier: :string,
          scheme: :string,
          status: "Enum8('success' = 0, 'failure' = 1)",
          git_branch: :string,
          git_commit_sha: :string,
          git_ref: :string,
          account_id: :i64,
          ran_at: "DateTime64(6)",
          inserted_at: "DateTime64(6)"
        }
      )

    # Create regular table with mappings (will be dropped after use)
    temp_table_name = "temp_event_to_test_run_#{:os.system_time(:second)}_#{:rand.uniform(1000)}"

    IngestRepo.query!("""
      CREATE TABLE #{temp_table_name} (
        event_id UUID,
        test_run_id UUID
      ) ENGINE = Memory
    """)

    # Build VALUES clause with proper UUID string format
    values_clauses =
      Enum.map(mappings, fn {event_id, test_run_id, _} ->
        event_uuid_str = Ecto.UUID.cast!(event_id)
        test_run_uuid_str = Ecto.UUID.cast!(test_run_id)
        "('#{event_uuid_str}', '#{test_run_uuid_str}')"
      end)
      |> Enum.join(", ")

    IngestRepo.query!(
      """
        INSERT INTO #{temp_table_name} (event_id, test_run_id)
        VALUES #{values_clauses}
      """,
      [],
      log: false
    )

    # Create a dictionary for efficient lookup
    dict_name = "event_to_test_run_dict_#{:os.system_time(:second)}_#{:rand.uniform(1000)}"

    IngestRepo.query!("""
      CREATE DICTIONARY #{dict_name} (
        event_id UUID,
        test_run_id UUID
      )
      PRIMARY KEY event_id
      SOURCE(CLICKHOUSE(TABLE '#{temp_table_name}'))
      LAYOUT(HASHED())
      LIFETIME(0)
    """)

    IngestRepo.query!("""
      ALTER TABLE command_events
      UPDATE test_run_id = dictGet('#{dict_name}', 'test_run_id', id)
      WHERE dictHas('#{dict_name}', id) AND name = 'test'
      SETTINGS mutations_sync = 1
    """)

    # Drop dictionary and table
    IngestRepo.query!("DROP DICTIONARY #{dict_name}")
    IngestRepo.query!("DROP TABLE #{temp_table_name}")

    batch_of_events |> Enum.map(& &1.created_at)
  end

  def page_query(last_created_at) do
    # Use created_at for cursor-based pagination to avoid loading all events into memory
    from(
      e in "command_events",
      select: %{
        id: e.id,
        project_id: e.project_id,
        duration: e.duration,
        macos_version: e.macos_version,
        swift_version: e.swift_version,
        is_ci: e.is_ci,
        subcommand: e.subcommand,
        status: e.status,
        git_branch: e.git_branch,
        git_commit_sha: e.git_commit_sha,
        git_ref: e.git_ref,
        user_id: e.user_id,
        ran_at: e.ran_at,
        created_at: e.created_at
      },
      where: e.name == "test" and is_nil(e.test_run_id) and e.created_at > ^last_created_at,
      order_by: [asc: e.created_at],
      limit: @batch_size
    )
  end

  defp create_test_run_from_event(event) do
    %{
      id: Ecto.UUID.generate(),
      project_id: event.project_id,
      duration: event.duration,
      macos_version: event.macos_version,
      xcode_version: event.swift_version,
      is_ci: event.is_ci,
      model_identifier: "",
      scheme: event.subcommand,
      status: event.status,
      git_branch: event.git_branch,
      git_commit_sha: event.git_commit_sha,
      git_ref: event.git_ref,
      account_id: event.user_id,
      ran_at: event.ran_at,
      inserted_at: event.created_at
    }
  end

  defp throttle_change_in_batches(
         query_fun,
         change_fun,
         last_created_at \\ ~N[1970-01-01 00:00:00]
       )

  defp throttle_change_in_batches(query_fun, change_fun, last_created_at) do
    case IngestRepo.all(query_fun.(last_created_at), log: :info, timeout: :infinity) do
      [] ->
        :ok

      events ->
        _results = change_fun.(events)
        # Get the last event's created_at since we're already sorted by created_at ASC
        next_created_at = events |> List.last() |> Map.get(:created_at)
        Process.sleep(@throttle_ms)
        throttle_change_in_batches(query_fun, change_fun, next_created_at)
    end
  end
end
