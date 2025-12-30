defmodule Tuist.Repo.Migrations.BackfillPreviewGroupsTable do
  use Ecto.Migration
  import Ecto.Query
  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    app_builds =
      from(a in "app_builds",
        select: %{
          id: a.id,
          project_id: a.project_id,
          ran_by_account_id: a.ran_by_account_id,
          display_name: a.display_name,
          bundle_identifier: a.bundle_identifier,
          version: a.version,
          git_branch: a.git_branch,
          git_commit_sha: a.git_commit_sha,
          supported_platforms: a.supported_platforms,
          type: a.type,
          inserted_at: a.inserted_at,
          updated_at: a.updated_at
        },
        order_by: [asc: a.inserted_at]
      )
      |> repo().all()

    previews =
      Enum.map(app_builds, fn app_build ->
        %{
          id: UUIDv7.bingenerate(),
          project_id: app_build.project_id,
          created_by_account_id: app_build.ran_by_account_id,
          display_name: app_build.display_name,
          bundle_identifier: app_build.bundle_identifier,
          version: app_build.version,
          git_branch: app_build.git_branch,
          git_commit_sha: app_build.git_commit_sha,
          supported_platforms: app_build.supported_platforms,
          visibility: if(app_build.type == :ipa, do: 0, else: 1),
          inserted_at: app_build.inserted_at |> DateTime.truncate(:second),
          updated_at: app_build.updated_at |> DateTime.truncate(:second)
        }
      end)

    {_count, _} =
      repo().insert_all("previews", previews)

    preview_ids =
      from(p in "previews",
        select: p.id,
        order_by: [asc: p.inserted_at]
      )
      |> repo().all()

    Enum.each(Enum.zip(Enum.map(app_builds, & &1.id), preview_ids), fn {app_build_id, preview_id} ->
      from(a in "app_builds",
        where: a.id == ^app_build_id,
        update: [set: [preview_id: ^preview_id]]
      )
      |> repo().update_all([])
    end)
  end

  def down, do: :ok
end
