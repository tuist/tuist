defmodule TuistTestSupport.Fixtures.PreviewsFixtures do
  @moduledoc false

  alias Tuist.Previews
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  def preview_fixture(opts \\ []) do
    project =
      Keyword.get_lazy(opts, :project, fn ->
        ProjectsFixtures.project_fixture()
      end)
      |> Tuist.Repo.preload([:account])

    type = Keyword.get(opts, :type, :app_bundle)
    display_name = Keyword.get(opts, :display_name, "App")
    bundle_identifier = Keyword.get(opts, :bundle_identifier, "com.tuist.app")
    version = Keyword.get(opts, :version, "1.0.0")
    supported_platforms = Keyword.get(opts, :supported_platforms, [:ios])
    git_branch = Keyword.get(opts, :git_branch, "main")
    git_commit_sha = Keyword.get(opts, :git_commit_sha, "7c184b7")
    ran_by_account_id = Keyword.get(opts, :ran_by_account_id, project.account.id)
    inserted_at = Keyword.get(opts, :inserted_at)

    Previews.create_preview(
      %{
        project: project,
        type: type,
        display_name: display_name,
        bundle_identifier: bundle_identifier,
        version: version,
        supported_platforms: supported_platforms,
        git_branch: git_branch,
        git_commit_sha: git_commit_sha,
        ran_by_account_id: ran_by_account_id
      },
      inserted_at: inserted_at
    )
  end
end
