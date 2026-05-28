defmodule Tuist.Storage.ExpiredArtifacts do
  @moduledoc false

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.AppBuilds
  alias Tuist.AppBuilds.AppBuild
  alias Tuist.AppBuilds.Preview
  alias Tuist.Builds
  alias Tuist.Builds.Build
  alias Tuist.ClickHouseRepo
  alias Tuist.Projects.Project
  alias Tuist.Repo
  alias Tuist.Shards
  alias Tuist.Shards.ShardPlan
  alias Tuist.Storage
  alias Tuist.Storage.RetentionPolicy
  alias Tuist.Tests
  alias Tuist.Tests.Test
  alias Tuist.Tests.TestCaseRunAttachment

  @candidate_multiplier 4

  def delete_previews(%Account{} = account, batch_size) do
    plan = RetentionPolicy.current_plan(account)
    cutoff = RetentionPolicy.cutoff(:preview_app_build, plan)

    candidates =
      AppBuild
      |> join(:inner, [app_build], preview in Preview, on: app_build.preview_id == preview.id)
      |> join(:inner, [_app_build, preview], project in Project, on: preview.project_id == project.id)
      |> where([app_build, _preview, project], project.account_id == ^account.id and app_build.inserted_at < ^cutoff)
      |> order_by([app_build], asc: app_build.inserted_at)
      |> limit(^candidate_limit(batch_size))
      |> select([app_build, preview, project], %{
        app_build: app_build,
        preview_id: preview.id,
        inserted_at: app_build.inserted_at,
        project_name: project.name
      })
      |> Repo.all()
      |> Enum.flat_map(fn candidate ->
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

        [
          %{object_key: app_build_key, inserted_at: candidate.inserted_at},
          %{object_key: icon_key, inserted_at: candidate.inserted_at}
        ]
      end)

    delete_candidates(account, candidates, batch_size)
  end

  def delete_build_archives(%Account{} = account, batch_size) do
    plan = RetentionPolicy.current_plan(account)
    cutoff = :build_archive |> RetentionPolicy.cutoff(plan) |> DateTime.to_naive()
    projects_by_id = projects_by_id(account)
    project_ids = Map.keys(projects_by_id)

    if project_ids == [] do
      :ok
    else
      Build
      |> where([build], build.project_id in ^project_ids and build.inserted_at < ^cutoff)
      |> order_by([build], asc: build.inserted_at)
      |> limit(^candidate_limit(batch_size))
      |> select([build], %{id: build.id, project_id: build.project_id, inserted_at: build.inserted_at})
      |> ClickHouseRepo.all()
      |> Enum.flat_map(fn build ->
        case Map.fetch(projects_by_id, build.project_id) do
          {:ok, project} ->
            [
              %{
                object_key: Builds.build_storage_key(account.name, project.name, build.id),
                inserted_at: build.inserted_at
              }
            ]

          :error ->
            []
        end
      end)
      |> then(&delete_candidates(account, &1, batch_size))
    end
  end

  def delete_test_attachments(%Account{} = account, batch_size) do
    plan = RetentionPolicy.current_plan(account)
    cutoff = :test_attachment |> RetentionPolicy.cutoff(plan) |> DateTime.to_naive()
    projects_by_id = projects_by_id(account)
    project_ids = Map.keys(projects_by_id)

    if project_ids == [] do
      :ok
    else
      TestCaseRunAttachment
      |> join(:inner, [attachment], test in Test, on: attachment.test_run_id == test.id)
      |> where(
        [attachment, test],
        test.project_id in ^project_ids and not is_nil(attachment.test_run_id) and attachment.inserted_at < ^cutoff
      )
      |> order_by([attachment], asc: attachment.inserted_at)
      |> limit(^candidate_limit(batch_size))
      |> select([attachment, test], %{
        attachment_id: attachment.id,
        test_case_run_id: attachment.test_case_run_id,
        test_run_id: attachment.test_run_id,
        file_name: attachment.file_name,
        inserted_at: attachment.inserted_at,
        project_id: test.project_id
      })
      |> ClickHouseRepo.all()
      |> Enum.flat_map(fn attachment ->
        case Map.fetch(projects_by_id, attachment.project_id) do
          {:ok, project} ->
            [
              %{
                object_key:
                  Tests.attachment_storage_key(%{
                    account_handle: account.name,
                    project_handle: project.name,
                    attachment_id: attachment.attachment_id,
                    test_case_run_id: attachment.test_case_run_id,
                    test_run_id: attachment.test_run_id,
                    file_name: attachment.file_name
                  }),
                inserted_at: attachment.inserted_at
              }
            ]

          :error ->
            []
        end
      end)
      |> then(&delete_candidates(account, &1, batch_size))
    end
  end

  def delete_shard_bundles(%Account{} = account, batch_size) do
    plan = RetentionPolicy.current_plan(account)
    cutoff = :shard_bundle |> RetentionPolicy.cutoff(plan) |> DateTime.to_naive()
    projects_by_id = projects_by_id(account)
    project_ids = Map.keys(projects_by_id)

    if project_ids == [] do
      :ok
    else
      ShardPlan
      |> where([shard_plan], shard_plan.project_id in ^project_ids and shard_plan.inserted_at < ^cutoff)
      |> order_by([shard_plan], asc: shard_plan.inserted_at)
      |> limit(^candidate_limit(batch_size))
      |> select([shard_plan], %{id: shard_plan.id, project_id: shard_plan.project_id, inserted_at: shard_plan.inserted_at})
      |> ClickHouseRepo.all()
      |> Enum.flat_map(fn shard_plan ->
        case Map.fetch(projects_by_id, shard_plan.project_id) do
          {:ok, project} ->
            [
              %{
                object_key: Shards.bundle_object_key(account, project, shard_plan.id),
                inserted_at: shard_plan.inserted_at
              }
            ]

          :error ->
            []
        end
      end)
      |> then(&delete_candidates(account, &1, batch_size))
    end
  end

  defp delete_candidates(%Account{} = account, candidates, batch_size) do
    candidates =
      candidates
      |> Enum.uniq_by(& &1.object_key)
      |> Enum.take(batch_size)

    candidates
    |> Enum.map(& &1.object_key)
    |> Storage.delete_objects(account)
  end

  defp projects_by_id(%Account{} = account) do
    Project
    |> where([project], project.account_id == ^account.id)
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  defp candidate_limit(batch_size), do: batch_size * @candidate_multiplier
end
