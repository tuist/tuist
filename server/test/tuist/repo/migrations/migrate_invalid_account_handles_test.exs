Code.require_file(
  Path.expand("../../../../priv/repo/migrations/20260917170000_migrate_invalid_account_handles.exs", __DIR__)
)

defmodule Tuist.Repo.Migrations.MigrateInvalidAccountHandlesTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Accounts.Account
  alias Tuist.Repo
  alias Tuist.Repo.Migrations.MigrateInvalidAccountHandles
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  test "replaces every run of invalid characters with a hyphen and drops hyphens at the ends" do
    unique = TuistTestSupport.Utilities.unique_integer()
    dotted = legacy_account("Legacy.Studio_#{unique}")
    spaced = legacy_account("  spaced + studio #{unique}  ")
    edged = legacy_account("-edge-#{unique}-")

    MigrateInvalidAccountHandles.migrate_invalid_handles!(Repo)

    assert handle(dotted) == "Legacy-Studio-#{unique}"
    assert handle(spaced) == "spaced-studio-#{unique}"
    assert handle(edged) == "edge-#{unique}"
  end

  test "leaves valid handles byte-for-byte" do
    unique = TuistTestSupport.Utilities.unique_integer()
    mixed_case = legacy_account("AnyStudio-#{unique}")
    longest = legacy_account(String.pad_trailing("a#{unique}", 32, "a"))

    MigrateInvalidAccountHandles.migrate_invalid_handles!(Repo)

    assert handle(mixed_case) == "AnyStudio-#{unique}"
    assert handle(longest) == String.pad_trailing("a#{unique}", 32, "a")
  end

  test "appends the lowest free number when the handle belongs to another account" do
    unique = TuistTestSupport.Utilities.unique_integer()
    legacy_account("legacy-studio-#{unique}")
    legacy_account("Legacy-Studio-#{unique}1")
    legacy = legacy_account("legacy.studio.#{unique}")

    MigrateInvalidAccountHandles.migrate_invalid_handles!(Repo)

    assert handle(legacy) == "legacy-studio-#{unique}2"
  end

  test "numbers the later of two legacy handles that become the same handle" do
    unique = TuistTestSupport.Utilities.unique_integer()
    first = legacy_account("legacy_studio_#{unique}")
    second = legacy_account("legacy.studio.#{unique}")

    MigrateInvalidAccountHandles.migrate_invalid_handles!(Repo)

    assert handle(first) == "legacy-studio-#{unique}"
    assert handle(second) == "legacy-studio-#{unique}1"
  end

  test "gives the unnumbered handle to the account that owns projects" do
    unique = TuistTestSupport.Utilities.unique_integer()
    without_projects = legacy_account("legacy_studio_#{unique}")
    with_projects = legacy_account("legacy.studio.#{unique}")
    ProjectsFixtures.project_fixture(account_id: with_projects.id)

    MigrateInvalidAccountHandles.migrate_invalid_handles!(Repo)

    assert handle(with_projects) == "legacy-studio-#{unique}"
    assert handle(without_projects) == "legacy-studio-#{unique}1"
  end

  test "numbers a handle that is reserved" do
    reserved = legacy_account("admin.")

    MigrateInvalidAccountHandles.migrate_invalid_handles!(Repo)

    assert handle(reserved) == "admin1"
  end

  test "shortens a handle to the longest one an account can hold, number included" do
    unique = TuistTestSupport.Utilities.unique_integer()
    base = String.pad_trailing("long.#{unique}.", 40, "a")
    expected = base |> String.replace(".", "-") |> String.slice(0, 32)
    legacy_account(String.slice(expected, 0, 31) <> "1")
    first = legacy_account(base)
    second = legacy_account(base <> "b")

    MigrateInvalidAccountHandles.migrate_invalid_handles!(Repo)

    assert handle(first) == expected
    assert handle(second) == String.slice(expected, 0, 31) <> "2"
  end

  test "names an account with nothing valid in its handle after its ID" do
    escape = legacy_account("\e[\e")

    MigrateInvalidAccountHandles.migrate_invalid_handles!(Repo)

    assert handle(escape) == "account-#{escape.id}"
  end

  test "leaves every account with a handle the account changeset accepts" do
    unique = TuistTestSupport.Utilities.unique_integer()

    accounts =
      Enum.map(["a b #{unique}", "_#{unique}_", "x.#{unique}+y", "-", "admin_"], &legacy_account/1)

    MigrateInvalidAccountHandles.migrate_invalid_handles!(Repo)

    for account <- accounts do
      # excellent_migrations:safety-assured-for-next-line operation_reload
      migrated = Repo.reload!(account)
      changeset = Account.update_changeset(%{migrated | name: nil}, %{name: migrated.name})

      assert changeset.valid?, "#{inspect(migrated.name)}: #{inspect(changeset.errors)}"
    end
  end

  test "is safe to run twice" do
    unique = TuistTestSupport.Utilities.unique_integer()
    legacy = legacy_account("legacy.studio.#{unique}")

    MigrateInvalidAccountHandles.migrate_invalid_handles!(Repo)
    MigrateInvalidAccountHandles.migrate_invalid_handles!(Repo)

    assert handle(legacy) == "legacy-studio-#{unique}"
  end

  # Handles registered before today's validation are written past it.
  defp legacy_account(name) do
    changeset = Ecto.Changeset.change(AccountsFixtures.user_fixture().account, name: name)

    # excellent_migrations:safety-assured-for-next-line operation_update
    Repo.update!(changeset)
  end

  defp handle(account) do
    # excellent_migrations:safety-assured-for-next-line operation_reload
    Repo.reload!(account).name
  end
end
