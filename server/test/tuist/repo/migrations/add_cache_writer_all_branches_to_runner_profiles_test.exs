Code.require_file(
  Path.expand(
    "../../../../priv/repo/migrations/20261020160000_add_cache_writer_all_branches_to_runner_profiles.exs",
    __DIR__
  )
)

defmodule Tuist.Repo.Migrations.AddCacheWriterAllBranchesToRunnerProfilesTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Repo.Migrations.AddCacheWriterAllBranchesToRunnerProfiles
  alias Tuist.Runners.Profile
  alias TuistTestSupport.Fixtures.AccountsFixtures

  test "keeps customized saving branches and lets every other profile save from every branch" do
    account = AccountsFixtures.account_fixture()
    untouched = [profile(account, platform: :linux), profile(account, platform: :macos, xcode_version: "26.6")]

    customized = [
      profile(account, cache_writer_branches: ["develop", "release/*"]),
      profile(account, cache_writer_branches: ["*"]),
      profile(account, cache_writer_default_branch: false)
    ]

    for profile <- untouched ++ customized, do: assert(profile.cache_writer_all_branches)

    assert %{num_rows: 3} = migrate()
    assert %{num_rows: 3} = migrate()

    # excellent_migrations:safety-assured-for-next-line operation_get
    for original <- untouched, do: assert(Repo.get!(Profile, original.id) == original)

    for original <- customized do
      # excellent_migrations:safety-assured-for-next-line operation_get
      migrated = Repo.get!(Profile, original.id)
      refute migrated.cache_writer_all_branches
      assert %{migrated | cache_writer_all_branches: true} == original
    end
  end

  # excellent_migrations:safety-assured-for-next-line operation_query
  defp migrate, do: Repo.query!(AddCacheWriterAllBranchesToRunnerProfiles.customized_statement())

  defp profile(account, attrs) do
    attrs =
      Map.merge(
        %{
          account_id: account.id,
          name: "ci-#{System.unique_integer([:positive])}",
          platform: :linux,
          vcpus: 4,
          memory_gb: 16,
          cache_writer_default_branch: true,
          cache_writer_branches: nil,
          updated_at: ~U[2026-10-01 00:00:00Z]
        },
        Map.new(attrs)
      )

    # excellent_migrations:safety-assured-for-next-line operation_insert
    Repo.insert!(struct!(Profile, attrs))
  end
end
