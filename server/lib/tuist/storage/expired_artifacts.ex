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
  alias Tuist.Storage.LegacyTestAttachmentRetentionCursor
  alias Tuist.Storage.RetentionPolicy
  alias Tuist.Tests
  alias Tuist.Tests.Test
  alias Tuist.Tests.TestCaseRunAttachment
  alias Tuist.Tests.TestCaseRunProject

  require Logger

  def delete_previews(%Account{} = account, batch_size, opts \\ []) do
    plan = RetentionPolicy.current_plan(account)
    cutoff = RetentionPolicy.cutoff(:preview_app_build, plan, Keyword.get(opts, :retention_days))
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
    cutoff = :build_archive |> RetentionPolicy.cutoff(plan, Keyword.get(opts, :retention_days)) |> DateTime.to_naive()
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

  def delete_run_artifacts(%Account{} = account, batch_size, opts \\ []) do
    plan = RetentionPolicy.current_plan(account)
    cutoff = :run_session |> RetentionPolicy.cutoff(plan, Keyword.get(opts, :retention_days)) |> DateTime.to_naive()
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

      prefixes =
        Enum.flat_map(rows, fn event ->
          case Map.fetch(projects_by_id, event.project_id) do
            {:ok, project} ->
              project = %{project | account: account}
              ["#{CommandEvents.get_command_event_artifact_base_path_key(event.id, project)}/"]

            :error ->
              []
          end
        end)

      delete_prefixes_and_continue(account, prefixes, next_cursor(rows, batch_size), progress_cursor(:run_session, rows))
    end
  end

  def delete_run_sessions(%Account{} = account, batch_size, opts \\ []) do
    delete_run_artifacts(account, batch_size, opts)
  end

  def delete_test_attachments(%Account{} = account, batch_size, opts \\ []) do
    plan = RetentionPolicy.current_plan(account)

    cutoff =
      :test_attachment
      |> RetentionPolicy.cutoff(plan, Keyword.get(opts, :retention_days))
      |> DateTime.to_naive()

    projects_by_id = projects_by_id(account)
    project_ids = Map.keys(projects_by_id)
    cursor = initial_cursor(account, :test_attachment, opts, :naive)

    if project_ids == [] do
      {:ok, nil}
    else
      rows =
        TestCaseRunAttachment
        |> join(:inner, [attachment], test_run in Test, on: attachment.test_run_id == test_run.id)
        |> where(
          [attachment, test_run],
          not is_nil(attachment.test_run_id) and test_run.project_id in ^project_ids and
            attachment.inserted_at < ^cutoff
        )
        |> apply_cursor(cursor)
        |> order_by([attachment], asc: attachment.inserted_at, asc: attachment.id)
        |> limit(^batch_size)
        |> select([attachment, test_run], %{
          id: attachment.id,
          test_case_run_id: attachment.test_case_run_id,
          test_run_id: attachment.test_run_id,
          file_name: attachment.file_name,
          inserted_at: attachment.inserted_at,
          project_id: test_run.project_id
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

  def delete_legacy_test_attachments(batch_size, opts \\ []) do
    retention_days = Keyword.get(opts, :retention_days, 30)
    dry_run? = Keyword.get(opts, :dry_run, true)
    cutoff = DateTime.utc_now() |> DateTime.add(-retention_days, :day) |> DateTime.to_naive()
    sweep = initial_legacy_test_attachment_sweep(opts, dry_run?, cutoff)

    rows =
      TestCaseRunAttachment
      |> where(
        [attachment],
        is_nil(attachment.test_run_id) and attachment.inserted_at < ^sweep.sweep_before
      )
      |> apply_legacy_test_attachment_completed_before(sweep.completed_before)
      |> apply_legacy_test_attachment_cursor(sweep.cursor)
      |> order_by([attachment], asc: attachment.test_case_run_id, asc: attachment.id)
      |> limit(^batch_size)
      |> select([attachment], %{
        id: attachment.id,
        test_case_run_id: attachment.test_case_run_id,
        file_name: attachment.file_name
      })
      |> ClickHouseRepo.all()

    test_case_runs_by_id =
      rows
      |> Enum.map(& &1.test_case_run_id)
      |> resolve_test_case_run_projects()

    projects_by_id =
      test_case_runs_by_id
      |> Map.values()
      |> Enum.uniq()
      |> projects_with_accounts_by_id()

    {objects_by_account_id, missing_test_case_run_count, deleted_project_count} =
      Enum.reduce(rows, {%{}, 0, 0}, fn attachment,
                                        {objects_by_account_id, missing_test_case_run_count, deleted_project_count} ->
        case Map.fetch(test_case_runs_by_id, attachment.test_case_run_id) do
          :error ->
            {objects_by_account_id, missing_test_case_run_count + 1, deleted_project_count}

          {:ok, project_id} ->
            case Map.fetch(projects_by_id, project_id) do
              :error ->
                {objects_by_account_id, missing_test_case_run_count, deleted_project_count + 1}

              {:ok, project} ->
                {
                  put_legacy_test_attachment_object(objects_by_account_id, project, attachment),
                  missing_test_case_run_count,
                  deleted_project_count
                }
            end
        end
      end)

    next_cursor = next_legacy_test_attachment_cursor(rows, batch_size, sweep)
    progress_cursor = legacy_test_attachment_progress_cursor(rows, next_cursor, sweep)

    cond do
      dry_run? ->
        object_count =
          Enum.reduce(objects_by_account_id, 0, fn {_account_id, {_account, object_keys}}, count ->
            count + length(object_keys)
          end)

        Logger.info(
          "Legacy test attachment retention dry run resolved #{object_count} objects across #{map_size(objects_by_account_id)} accounts with #{missing_test_case_run_count} missing test case runs and #{deleted_project_count} deleted projects; #{legacy_test_attachment_sweep_position(sweep, rows)}"
        )

        {:ok, next_cursor}

      missing_test_case_run_count > 0 ->
        {:error, {:unresolved_legacy_test_attachments, missing_test_case_run_count}}

      true ->
        maybe_log_deleted_legacy_test_attachment_projects(deleted_project_count, sweep, rows)

        with :ok <- delete_legacy_test_attachment_objects(objects_by_account_id),
             :ok <- persist_legacy_test_attachment_cursor(progress_cursor, sweep) do
          {:ok, next_cursor}
        end
    end
  end

  def delete_shard_bundles(%Account{} = account, batch_size, opts \\ []) do
    plan = RetentionPolicy.current_plan(account)
    cutoff = :shard_bundle |> RetentionPolicy.cutoff(plan, Keyword.get(opts, :retention_days)) |> DateTime.to_naive()
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

  defp delete_prefixes_and_continue(%Account{} = account, prefixes, next_cursor, progress_cursor) do
    prefixes |> Enum.uniq() |> Enum.each(&Storage.delete_all_objects(&1, account))

    with :ok <- persist_progress_cursor(account, progress_cursor) do
      {:ok, next_cursor}
    end
  end

  defp projects_by_id(%Account{} = account) do
    Project
    |> where([project], project.account_id == ^account.id)
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  defp projects_with_accounts_by_id([]), do: %{}

  defp projects_with_accounts_by_id(project_ids) do
    Project
    |> where([project], project.id in ^project_ids)
    |> preload(:account)
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  defp resolve_test_case_run_projects([]), do: %{}

  defp resolve_test_case_run_projects(test_case_run_ids) do
    TestCaseRunProject
    |> from(hints: ["FINAL"])
    |> where([test_case_run], test_case_run.id in ^test_case_run_ids)
    |> select([test_case_run], {test_case_run.id, test_case_run.project_id})
    |> ClickHouseRepo.all()
    |> Map.new()
  end

  defp delete_legacy_test_attachment_objects(objects_by_account_id) do
    Enum.reduce_while(objects_by_account_id, :ok, fn {_account_id, {account, object_keys}}, :ok ->
      case Storage.delete_objects(Enum.uniq(object_keys), account) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp put_legacy_test_attachment_object(objects_by_account_id, project, attachment) do
    object_key =
      Tests.attachment_storage_key(%{
        account_handle: project.account.name,
        project_handle: project.name,
        attachment_id: attachment.id,
        test_case_run_id: attachment.test_case_run_id,
        test_run_id: nil,
        file_name: attachment.file_name
      })

    Map.update(
      objects_by_account_id,
      project.account.id,
      {project.account, [object_key]},
      fn {account, object_keys} -> {account, [object_key | object_keys]} end
    )
  end

  defp maybe_log_deleted_legacy_test_attachment_projects(0, _sweep, _rows), do: :ok

  defp maybe_log_deleted_legacy_test_attachment_projects(count, sweep, rows) do
    Logger.warning(
      "Legacy test attachment retention skipped #{count} rows whose projects have been deleted; #{legacy_test_attachment_sweep_position(sweep, rows)}"
    )
  end

  defp legacy_test_attachment_sweep_position(sweep, rows) do
    last = List.last(rows)

    "completed_before=#{inspect(sweep.completed_before)} sweep_before=#{inspect(sweep.sweep_before)} " <>
      "after_test_case_run_id=#{inspect(last && last.test_case_run_id)} after_id=#{inspect(last && last.id)}"
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

  defp apply_legacy_test_attachment_cursor(query, nil), do: query

  defp apply_legacy_test_attachment_cursor(query, {test_case_run_id, attachment_id}) do
    where(
      query,
      [attachment],
      attachment.test_case_run_id > ^test_case_run_id or
        (attachment.test_case_run_id == ^test_case_run_id and attachment.id > ^attachment_id)
    )
  end

  defp apply_legacy_test_attachment_completed_before(query, nil), do: query

  defp apply_legacy_test_attachment_completed_before(query, completed_before) do
    where(query, [attachment], attachment.inserted_at >= ^completed_before)
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

  defp initial_legacy_test_attachment_sweep(opts, dry_run?, cutoff) do
    case parse_legacy_test_attachment_sweep(opts) do
      {:ok, sweep} ->
        sweep

      :error when dry_run? ->
        %{completed_before: nil, sweep_before: cutoff, cursor: nil}

      :error ->
        persisted_legacy_test_attachment_sweep(cutoff)
    end
  end

  defp parse_legacy_test_attachment_sweep(opts) do
    with sweep_before when is_binary(sweep_before) <- Keyword.get(opts, :sweep_before),
         {:ok, sweep_before} <- parse_inserted_at(sweep_before, :naive),
         {:ok, completed_before} <-
           parse_optional_inserted_at(Keyword.get(opts, :completed_before), :naive) do
      {:ok,
       %{
         completed_before: completed_before,
         sweep_before: sweep_before,
         cursor: parse_legacy_test_attachment_cursor(opts)
       }}
    else
      _ -> :error
    end
  end

  defp parse_legacy_test_attachment_cursor(opts) do
    case {Keyword.get(opts, :after_test_case_run_id), Keyword.get(opts, :after_id)} do
      {test_case_run_id, attachment_id}
      when is_binary(test_case_run_id) and is_binary(attachment_id) ->
        {test_case_run_id, attachment_id}

      _ ->
        nil
    end
  end

  defp persisted_legacy_test_attachment_sweep(cutoff) do
    case Repo.get_by(LegacyTestAttachmentRetentionCursor, artifact_type: :legacy_test_attachment) do
      nil ->
        %{completed_before: nil, sweep_before: cutoff, cursor: nil}

      %LegacyTestAttachmentRetentionCursor{
        after_test_case_run_id: test_case_run_id,
        after_id: attachment_id
      } = cursor
      when not is_nil(test_case_run_id) and not is_nil(attachment_id) ->
        %{
          completed_before: stored_inserted_at(cursor.completed_before, :naive),
          sweep_before: stored_inserted_at(cursor.sweep_before, :naive),
          cursor: {test_case_run_id, attachment_id}
        }

      %LegacyTestAttachmentRetentionCursor{} = cursor ->
        %{
          completed_before: stored_inserted_at(cursor.completed_before, :naive),
          sweep_before: cutoff,
          cursor: nil
        }
    end
  end

  defp parse_optional_inserted_at(nil, _kind), do: {:ok, nil}
  defp parse_optional_inserted_at(value, kind), do: parse_inserted_at(value, kind)

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

  defp next_legacy_test_attachment_cursor(rows, batch_size, _sweep) when length(rows) < batch_size, do: nil

  defp next_legacy_test_attachment_cursor(rows, _batch_size, sweep) do
    last = List.last(rows)

    maybe_put_completed_before(
      %{
        "after_test_case_run_id" => last.test_case_run_id,
        "after_id" => last.id,
        "sweep_before" => inserted_at_to_iso(sweep.sweep_before)
      },
      sweep.completed_before
    )
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

  defp legacy_test_attachment_progress_cursor(_rows, nil, sweep) do
    %{
      artifact_type: :legacy_test_attachment,
      completed_before: progress_inserted_at(sweep.sweep_before),
      sweep_before: progress_inserted_at(sweep.sweep_before),
      after_test_case_run_id: nil,
      after_id: nil
    }
  end

  defp legacy_test_attachment_progress_cursor(rows, _next_cursor, sweep) do
    last = List.last(rows)

    %{
      artifact_type: :legacy_test_attachment,
      completed_before: optional_progress_inserted_at(sweep.completed_before),
      sweep_before: progress_inserted_at(sweep.sweep_before),
      after_test_case_run_id: last.test_case_run_id,
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

  defp persist_legacy_test_attachment_cursor(progress_cursor, sweep) do
    case Repo.transaction(fn ->
           persisted_cursor =
             LegacyTestAttachmentRetentionCursor
             |> where([cursor], cursor.artifact_type == :legacy_test_attachment)
             |> lock("FOR UPDATE")
             |> Repo.one()

           persist_legacy_test_attachment_cursor_change(persisted_cursor, progress_cursor, sweep)
         end) do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp persist_legacy_test_attachment_cursor_change(persisted_cursor, progress_cursor, sweep) do
    if legacy_test_attachment_sweep_matches?(persisted_cursor, sweep) do
      persisted_cursor
      |> Kernel.||(%LegacyTestAttachmentRetentionCursor{})
      |> LegacyTestAttachmentRetentionCursor.changeset(progress_cursor)
      |> Repo.insert_or_update()
      |> case do
        {:ok, _cursor} -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end
    else
      Repo.rollback(:stale_legacy_test_attachment_cursor)
    end
  end

  defp legacy_test_attachment_sweep_matches?(nil, _sweep), do: true

  defp legacy_test_attachment_sweep_matches?(persisted_cursor, %{cursor: nil} = sweep) do
    is_nil(persisted_cursor.after_test_case_run_id) and
      is_nil(persisted_cursor.after_id) and
      stored_inserted_at(persisted_cursor.completed_before, :naive) == sweep.completed_before
  end

  defp legacy_test_attachment_sweep_matches?(persisted_cursor, %{cursor: {test_case_run_id, attachment_id}} = sweep) do
    stored_inserted_at(persisted_cursor.completed_before, :naive) == sweep.completed_before and
      stored_inserted_at(persisted_cursor.sweep_before, :naive) == sweep.sweep_before and
      persisted_cursor.after_test_case_run_id == test_case_run_id and
      persisted_cursor.after_id == attachment_id
  end

  defp stored_inserted_at(%DateTime{} = inserted_at, :utc), do: inserted_at
  defp stored_inserted_at(%DateTime{} = inserted_at, :naive), do: DateTime.to_naive(inserted_at)
  defp stored_inserted_at(nil, _kind), do: nil

  defp progress_inserted_at(%DateTime{} = inserted_at), do: inserted_at
  defp progress_inserted_at(%NaiveDateTime{} = inserted_at), do: DateTime.from_naive!(inserted_at, "Etc/UTC")
  defp optional_progress_inserted_at(nil), do: nil
  defp optional_progress_inserted_at(inserted_at), do: progress_inserted_at(inserted_at)

  defp inserted_at_to_iso(%DateTime{} = inserted_at), do: DateTime.to_iso8601(inserted_at)
  defp inserted_at_to_iso(%NaiveDateTime{} = inserted_at), do: NaiveDateTime.to_iso8601(inserted_at)

  defp maybe_put_completed_before(cursor, nil), do: cursor

  defp maybe_put_completed_before(cursor, completed_before) do
    Map.put(cursor, "completed_before", inserted_at_to_iso(completed_before))
  end
end
