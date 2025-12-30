defmodule TuistTestSupport.Fixtures.BundlesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  bundle-related entities via the `Tuist.Bundles` context.
  """

  alias Tuist.Bundles
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  @doc """
  Generates a bundle.
  """
  def bundle_fixture(opts \\ []) do
    id = UUIDv7.generate()
    project = Keyword.get(opts, :project, ProjectsFixtures.project_fixture())
    preload = Keyword.get(opts, :preload, [:uploaded_by_account])

    uploaded_by_account =
      Keyword.get(
        opts,
        :uploaded_by_account,
        AccountsFixtures.user_fixture(preload: [:account]).account
      )

    {:ok, bundle} =
      Bundles.create_bundle(%{
        id: id,
        name: Keyword.get(opts, :name, "App"),
        app_bundle_id: "dev.tuist.app",
        install_size: Keyword.get(opts, :install_size, 1024),
        download_size: Keyword.get(opts, :download_size, 1024),
        supported_platforms:
          Keyword.get(opts, :supported_platforms, [
            :ios,
            :ios_simulator
          ]),
        version: "1.0.0",
        git_branch: Keyword.get(opts, :git_branch, "main"),
        git_commit_sha: Keyword.get(opts, :git_commit_sha),
        git_ref: Keyword.get(opts, :git_ref),
        type: Keyword.get(opts, :type, :app),
        project_id: project.id,
        uploaded_by_account_id: uploaded_by_account.id,
        inserted_at: Keyword.get(opts, :inserted_at, DateTime.utc_now()),
        artifacts: Keyword.get(opts, :artifacts, [])
      })

    Repo.preload(bundle, preload)
  end
end
