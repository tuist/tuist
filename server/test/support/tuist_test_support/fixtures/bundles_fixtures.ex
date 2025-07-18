defmodule TuistTestSupport.Fixtures.BundlesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  bundle-related entities via the `Tuist.Bundles` context.
  """

  alias Tuist.Bundles
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  @doc """
  Generates a bundle.
  """
  def bundle_fixture(opts \\ []) do
    id = UUIDv7.generate()

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
        project_id: Keyword.get(opts, :project_id, ProjectsFixtures.project_fixture().id),
        inserted_at: Keyword.get(opts, :inserted_at, DateTime.utc_now())
      })

    bundle
  end
end
