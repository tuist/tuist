defmodule Tuist.Storage.ExpiredArtifacts do
  @moduledoc """
  Per-account deletion of expired artifact blobs from object storage.

  Each `delete_*` function processes a single keyset-paginated batch ordered by
  `(inserted_at, id)` and returns `{:ok, next_cursor}`. `next_cursor` is `nil`
  when the batch wasn't full (no more expired rows), otherwise a serializable
  map (`%{"after_inserted_at" => ..., "after_id" => ...}`) that the calling
  worker feeds back into the next job to resume after the last processed row.

  The metadata rows themselves are intentionally left in place (they back
  dashboards and analytics); persisted per-account cursors are what let
  scheduled runs walk past blobs that were already deleted.
  """

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.AppBuilds
  alias Tuist.AppBuilds.AppBuild
  alias Tuist.AppBuilds.Preview
  alias Tuist.Builds
  alias Tuist.Builds.Build
  alias Tuist.ClickHouseRepo
  alias Tuist.CommandEvents
  alias Tuist.CommandEvents.Event
  alias Tuist.Projects.Project
  alias Tuist.Repo
  alias Tuist.Shards
  alias Tuist.Shards.ShardPlan
  alias Tuist.Storage
  alias Tuist.Storage.ArtifactRetentionCursor
  alias Tuist.Storage.RetentionPolicy
  alias Tuist.Tests
  alias Tuist.Tests.TestCaseRun
  alias Tuist.Tests.TestCaseRunAttachment

  def delete_previews(%Account{} = account, batch_size, opts \\ []) do
    plan = RetentionPolicy.current_plan(account)
    cutoff = RetentionPolicy.cutoff(:preview_app_build, plan)
    cursor = initial_cursor(account, :preview_app_build, opts, :utc)

    rows =
      AppBuild
      |> join(:inner, [app_build], preview in Preview, on: app_build.preview_id == preview.id)
      |> join(:inner, [_app_build, preview], project in Project, on: preview.project_id == project.id)
      |> where([app_build, _preview, project], project.account_id == ^account.id and app_build.inserted_at < ^cutoff)
      |> apply_cursor(cursor)
      |> order_by([app_build], asc: app_build.inserted_at, asc: app_build.id)
      |> limit(^batch_size)
      |> select([app_build, preview, project], %{
        app_build: app_build,
        id: app_build.id,
        preview_id: preview.id,
        inserted_at: app_build.inserted_at,
        project_name: project.name
      })
      |> Repo.all()

    object_keys =
      Enum.flat_map(rows, fn candidate ->
        app_build_key =
          AppBuilds.storage_key(%{
            account_handle: account.name,
            project_handle: candidate.project_name,
            app_build: candidate.app_build
          })

        icon_key =
          AppBuilds.icon_storage_key(%{
            account_handle: account.name,
            project_handle: candidate.project_name,
            preview_id: candidate.preview_id
          })

        [app_build_key, icon_key]
      end)

    delete_and_continue(account, object_keys, next_cursor(rows, batch_size), progress_cursor(:preview_app_build, rows))
  end

  def delete_build_archives(%Account{} = account, batch_size, opts \\ []) do
    plan = RetentionPolicy.current_plan(account)
    cutoff = :build_archive |> RetentionPolicy.cutoff(plan) |> DateTime.to_naive()
    projects_by_id = projects_by_id(account)
    project_ids = Map.keys(projects_by_id)
    cursor = initial_cursor(account, :build_archive, opts, :naive)

    if project_ids == [] do
      {:ok, nil}
    else
      rows =
        Build
        |> where([build], build.project_id in ^project_ids and build.inserted_at < ^cutoff)
        |> apply_cursor(cursor)
        |> order_by([build], asc: build.inserted_at, asc: build.id)
        |> limit(^batch_size)
        |> select([build], %{id: build.id, project_id: build.project_id, inserted_at: build.inserted_at})
        |> ClickHouseRepo.all()

      object_keys =
        Enum.flat_map(rows, fn build ->
          case Map.fetch(projects_by_id, build.project_id) do
            {:ok, project} -> [Builds.build_storage_key(account.name, project.name, build.id)]
            :error -> []
          end
        end)

      delete_and_continue(account, object_keys, next_cursor(rows, batch_size), progress_cursor(:build_archive, rows))
    end
  end

  def delete_run_sessions(%Account{} = account, batch_size, opts \\ []) do
    plan = RetentionPolicy.current_plan(account)
    cutoff = :run_session |> RetentionPolicy.cutoff(plan) |> DateTime.to_naive()
    projects_by_id = projects_by_id(account)
    project_ids = Map.keys(projects_by_id)
    cursor = initial_cursor(account, :run_session, opts, :naive)

    if project_ids == [] do
      {:ok, nil}
    else
      rows =
        Event
        |> where([event], event.project_id in ^project_ids and event.ran_at < ^cutoff)
        |> apply_cursor(cursor, :ran_at)
        |> order_by([event], asc: event.ran_at, asc: event.id)
        |> limit(^batch_size)
        |> select([event], %{id: event.id, project_id: event.project_id, inserted_at: event.ran_at})
        |> ClickHouseRepo.all()

      object_keys =
        Enum.flat_map(rows, fn event ->
          case Map.fetch(projects_by_id, event.project_id) do
            {:ok, project} -> [CommandEvents.get_session_key(event.id, %{project | account: account})]
            :error -> []
          end
        end)

      delete_and_continue(account, object_keys, next_cursor(rows, batch_size), progress_cursor(:run_session, rows))
    end
  end

  def delete_test_attachments(%Account{} = account, batch_size, opts \\ []) do
    plan = RetentionPolicy.current_plan(account)
    cutoff = :test_attachment |> RetentionPolicy.cutoff(plan) |> DateTime.to_naive()
    projects_by_id = projects_by_id(account)
    project_ids = Map.keys(projects_by_id)
    cursor = initial_cursor(account, :test_attachment, opts, :naive)

    if project_ids == [] do
      {:ok, nil}
    else
      rows =
        TestCaseRunAttachment
        |> join(:inner, [attachment], test_case_run in TestCaseRun, on: attachment.test_case_run_id == test_case_run.id)
        |> where(
          [attachment, test_case_run],
          test_case_run.project_id in ^project_ids and attachment.inserted_at < ^cutoff
        )
        |> apply_cursor(cursor)
        |> order_by([attachment], asc: attachment.inserted_at, asc: attachment.id)
        |> limit(^batch_size)
        |> select([attachment, test_case_run], %{
          id: attachment.id,
          test_case_run_id: attachment.test_case_run_id,
          test_run_id: attachment.test_run_id,
          file_name: attachment.file_name,
          inserted_at: attachment.inserted_at,
          project_id: test_case_run.project_id
        })
        |> ClickHouseRepo.all()

      object_keys =
        Enum.flat_map(rows, fn attachment ->
          case Map.fetch(projects_by_id, attachment.project_id) do
            {:ok, project} ->
              [
                Tests.attachment_storage_key(%{
                  account_handle: account.name,
                  project_handle: project.name,
                  attachment_id: attachment.id,
                  test_case_run_id: attachment.test_case_run_id,
                  test_run_id: attachment.test_run_id,
                  file_name: attachment.file_name
                })
              ]

            :error ->
              []
          end
        end)

      delete_and_continue(account, object_keys, next_cursor(rows, batch_size), progress_cursor(:test_attachment, rows))
    end
  end

  def delete_shard_bundles(%Account{} = account, batch_size, opts \\ []) do
    plan = RetentionPolicy.current_plan(account)
    cutoff = :shard_bundle |> RetentionPolicy.cutoff(plan) |> DateTime.to_naive()
    projects_by_id = projects_by_id(account)
    project_ids = Map.keys(projects_by_id)
    cursor = initial_cursor(account, :shard_bundle, opts, :naive)

    if project_ids == [] do
      {:ok, nil}
    else
      rows =
        ShardPlan
        |> where([shard_plan], shard_plan.project_id in ^project_ids and shard_plan.inserted_at < ^cutoff)
        |> apply_cursor(cursor)
        |> order_by([shard_plan], asc: shard_plan.inserted_at, asc: shard_plan.id)
        |> limit(^batch_size)
        |> select([shard_plan], %{
          id: shard_plan.id,
          project_id: shard_plan.project_id,
          inserted_at: shard_plan.inserted_at
        })
        |> ClickHouseRepo.all()

      object_keys =
        Enum.flat_map(rows, fn shard_plan ->
          case Map.fetch(projects_by_id, shard_plan.project_id) do
            {:ok, project} -> [Shards.bundle_object_key(account, project, shard_plan.id)]
            :error -> []
          end
        end)

      delete_and_continue(account, object_keys, next_cursor(rows, batch_size), progress_cursor(:shard_bundle, rows))
    end
  end

  defp delete_and_continue(%Account{} = account, object_keys, next_cursor, progress_cursor) do
    case object_keys |> Enum.uniq() |> Storage.delete_objects(account) do
      :ok ->
        with :ok <- persist_progress_cursor(account, progress_cursor) do
          {:ok, next_cursor}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp projects_by_id(%Account{} = account) do
    Project
    |> where([project], project.account_id == ^account.id)
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  defp apply_cursor(query, cursor), do: apply_cursor(query, cursor, :inserted_at)

  defp apply_cursor(query, nil, _field), do: query

  defp apply_cursor(query, {inserted_at, id}, field) do
    where(
      query,
      [row],
      field(row, ^field) > ^inserted_at or (field(row, ^field) == ^inserted_at and row.id > ^id)
    )
  end

  defp initial_cursor(%Account{} = account, artifact_type, opts, kind) do
    case parse_cursor(opts, kind) do
      nil -> persisted_cursor(account, artifact_type, kind)
      cursor -> cursor
    end
  end

  defp parse_cursor(opts, kind) do
    with after_inserted_at when is_binary(after_inserted_at) <- Keyword.get(opts, :after_inserted_at),
         after_id when not is_nil(after_id) <- Keyword.get(opts, :after_id),
         {:ok, inserted_at} <- parse_inserted_at(after_inserted_at, kind) do
      {inserted_at, after_id}
    else
      _ -> nil
    end
  end

  defp persisted_cursor(%Account{id: account_id}, artifact_type, kind) do
    case Repo.get_by(ArtifactRetentionCursor, account_id: account_id, artifact_type: artifact_type) do
      nil ->
        nil

      %ArtifactRetentionCursor{} = cursor ->
        {stored_inserted_at(cursor.after_inserted_at, kind), cursor.after_id}
    end
  end

  defp parse_inserted_at(value, :utc) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, _reason} -> :error
    end
  end

  defp parse_inserted_at(value, :naive), do: NaiveDateTime.from_iso8601(value)

  defp next_cursor(rows, batch_size) when length(rows) < batch_size, do: nil

  defp next_cursor(rows, _batch_size) do
    last = List.last(rows)
    %{"after_inserted_at" => inserted_at_to_iso(last.inserted_at), "after_id" => last.id}
  end

  defp progress_cursor(_artifact_type, []), do: nil

  defp progress_cursor(artifact_type, rows) do
    last = List.last(rows)

    %{
      artifact_type: artifact_type,
      after_inserted_at: progress_inserted_at(last.inserted_at),
      after_id: last.id
    }
  end

  defp persist_progress_cursor(_account, nil), do: :ok

  defp persist_progress_cursor(%Account{id: account_id}, progress_cursor) do
    after_inserted_at = progress_cursor.after_inserted_at
    after_id = progress_cursor.after_id
    updated_at = DateTime.truncate(DateTime.utc_now(), :second)
    attrs = Map.put(progress_cursor, :account_id, account_id)

    on_conflict =
      from(cursor in ArtifactRetentionCursor,
        where:
          ^after_inserted_at > cursor.after_inserted_at or
            (^after_inserted_at == cursor.after_inserted_at and ^after_id > cursor.after_id),
        update: [
          set: [
            after_inserted_at: ^after_inserted_at,
            after_id: ^after_id,
            updated_at: ^updated_at
          ]
        ]
      )

    %ArtifactRetentionCursor{}
    |> ArtifactRetentionCursor.changeset(attrs)
    |> Repo.insert(
      on_conflict: on_conflict,
      conflict_target: [:account_id, :artifact_type],
      allow_stale: true
    )
    |> case do
      {:ok, _cursor} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp stored_inserted_at(%DateTime{} = inserted_at, :utc), do: inserted_at
  defp stored_inserted_at(%DateTime{} = inserted_at, :naive), do: DateTime.to_naive(inserted_at)

  defp progress_inserted_at(%DateTime{} = inserted_at), do: inserted_at
  defp progress_inserted_at(%NaiveDateTime{} = inserted_at), do: DateTime.from_naive!(inserted_at, "Etc/UTC")

  defp inserted_at_to_iso(%DateTime{} = inserted_at), do: DateTime.to_iso8601(inserted_at)
  defp inserted_at_to_iso(%NaiveDateTime{} = inserted_at), do: NaiveDateTime.to_iso8601(inserted_at)
end
