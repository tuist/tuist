defmodule TuistTestSupport.Fixtures.BundlesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  bundle-related entities via the `Tuist.Bundles` context.
  """

  alias Tuist.Bundles
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  @doc """
  Generates a bundle.
  """
  def bundle_fixture(opts \\ []) do
    id = UUIDv7.generate()
    project = Keyword.get(opts, :project, ProjectsFixtures.project_fixture())
    
    # Get or create an account for uploaded_by_account_id
    uploaded_by_account = case Keyword.get(opts, :uploaded_by_account) do
      nil -> 
        case Keyword.get(opts, :uploaded_by_user) do
          nil -> AccountsFixtures.user_fixture(preload: [:account]).account
          user -> user.account
        end
      account -> account
    end

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
        project_id: project.id,
        uploaded_by_account_id: uploaded_by_account.id,
        inserted_at: Keyword.get(opts, :inserted_at, DateTime.utc_now()),
        artifacts: Keyword.get(opts, :artifacts, [])
      })

    bundle
  end
end
