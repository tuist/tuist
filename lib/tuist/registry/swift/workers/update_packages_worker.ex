defmodule Tuist.Registry.Swift.Workers.UpdatePackagesWorker do
  @moduledoc """
  A worker that adds a new Swift package and populates all its releases.
  """
  alias Tuist.VCS.Repositories.Content
  alias Tuist.Environment
  alias Tuist.Registry.Swift.Packages

  use Oban.Worker,
    unique: [
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable]
    ],
    max_attempts: 3

  alias Tuist.VCS

  # Packages with git submodules are not supported to be automatically mirrored in our registry.
  @unsupported_packages [
    "monzo/nearby",
    "awslabs/aws-crt-swift"
  ]

  @impl Oban.Worker
  def perform(%Oban.Job{} = _job) do
    token = Environment.github_token_update_packages()

    {:ok, %Content{content: content}} =
      VCS.get_repository_content(
        %{
          repository_full_handle: "SwiftPackageIndex/PackageList",
          provider: :github,
          token: token
        },
        path: "packages.json"
      )

    packages =
      content
      |> Jason.decode!()
      |> Enum.map(&VCS.get_repository_full_handle_from_url/1)
      |> Enum.map(&elem(&1, 1))
      |> Enum.filter(&(not Enum.member?(@unsupported_packages, &1)))
      |> Enum.map(&Packages.get_package_scope_and_name_from_repository_full_handle/1)

    remove_packages_no_longer_present(packages)

    create_missing_packages(%{packages: packages, token: token})
  end

  defp remove_packages_no_longer_present(packages) do
    packages =
      packages |> Enum.map(&Map.take(&1, [:repository_full_handle])) |> MapSet.new()

    Packages.all_packages()
    |> Enum.filter(
      &(!MapSet.member?(packages, %{
          repository_full_handle: &1.repository_full_handle
        }))
    )
    # This is only to ensure we don't accidentally delete all packages in case we introduce a bug in the filtering logic.
    |> Enum.take(100)
    |> Enum.each(&Packages.delete_package/1)
  end

  defp create_missing_packages(%{packages: packages, token: token}) do
    packages
    |> Enum.filter(&is_nil(Packages.get_package_by_scope_and_name(&1)))
    # We don't want to exhaust the API limit of the token.
    |> Enum.take(100)
    |> Enum.map(&Packages.create_package/1)
    |> Enum.each(&Packages.create_missing_package_releases(%{package: &1, token: token}))
  end
end
