defmodule TuistTestSupport.Fixtures.AppBuildsFixtures do
  @moduledoc false

  alias Tuist.AppBuilds.AppBuild
  alias Tuist.AppBuilds.Preview
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  def preview_fixture(opts \\ []) do
    project =
      opts
      |> Keyword.get_lazy(:project, fn ->
        ProjectsFixtures.project_fixture()
      end)
      |> Repo.preload([:account])

    %Preview{}
    |> Preview.create_changeset(%{
      project_id: project.id,
      display_name: Keyword.get(opts, :display_name, "App"),
      bundle_identifier: Keyword.get(opts, :bundle_identifier, "dev.tuist.app"),
      version: Keyword.get(opts, :version, "1.0.0"),
      git_branch: Keyword.get(opts, :git_branch, "main"),
      git_commit_sha: Keyword.get_lazy(opts, :git_commit_sha, fn -> UUIDv7.generate() end),
      git_ref: Keyword.get(opts, :git_ref, "refs/heads/main"),
      track: Keyword.get(opts, :track, ""),
      created_by_account_id: Keyword.get(opts, :created_by_account_id, project.account.id),
      visibility: Keyword.get(opts, :visibility),
      supported_platforms: Keyword.get(opts, :supported_platforms, []),
      inserted_at: Keyword.get(opts, :inserted_at)
    })
    |> Repo.insert!()
  end

  def app_build_fixture(opts \\ []) do
    preview =
      Keyword.get_lazy(opts, :preview, fn ->
        preview_fixture()
      end)

    %AppBuild{}
    |> AppBuild.create_changeset(%{
      preview_id: preview.id,
      type: Keyword.get(opts, :type, :app_bundle),
      supported_platforms: Keyword.get(opts, :supported_platforms, [:ios]),
      binary_id: Keyword.get(opts, :binary_id),
      build_version: Keyword.get(opts, :build_version),
      inserted_at: Keyword.get(opts, :inserted_at)
    })
    |> Repo.insert!()
    |> Repo.preload(Keyword.get(opts, :preload, []))
  end
end
