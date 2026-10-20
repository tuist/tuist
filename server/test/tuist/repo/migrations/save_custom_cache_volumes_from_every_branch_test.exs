Code.require_file(
  Path.expand(
    "../../../../priv/repo/migrations/20261020140000_save_custom_cache_volumes_from_every_branch.exs",
    __DIR__
  )
)

defmodule Tuist.Repo.Migrations.SaveCustomCacheVolumesFromEveryBranchTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Repo.Migrations.SaveCustomCacheVolumesFromEveryBranch
  alias Tuist.Runners.Profile
  alias TuistTestSupport.Fixtures.AccountsFixtures

  test "saves from every branch on profiles that kept the previous default and leaves customized ones alone" do
    account = AccountsFixtures.account_fixture()
    previous_default = [profile(account, platform: :linux), profile(account, platform: :macos, xcode_version: "26.6")]

    customized = [
      profile(account, cache_writer_branches: ["develop", "release/*"]),
      profile(account, cache_writer_branches: ["*"]),
      profile(account, cache_writer_default_branch: false),
      profile(account, cache_writer_default_branch: false, cache_writer_branches: ["release/*"])
    ]

    assert %{num_rows: 2} = migrate()
    assert %{num_rows: 0} = migrate()

    for original <- previous_default do
      # excellent_migrations:safety-assured-for-next-line operation_get
      migrated = Repo.get!(Profile, original.id)
      assert migrated.cache_writer_branches == ["*"]
      assert migrated.cache_writer_default_branch
      assert DateTime.after?(migrated.updated_at, original.updated_at)
    end

    # excellent_migrations:safety-assured-for-next-line operation_get
    for original <- customized, do: assert(Repo.get!(Profile, original.id) == original)
  end

  test "rollback keeps the profiles' policy" do
    assert :ok = SaveCustomCacheVolumesFromEveryBranch.down()
  end

  # excellent_migrations:safety-assured-for-next-line operation_query
  defp migrate, do: Repo.query!(SaveCustomCacheVolumesFromEveryBranch.statement())

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
