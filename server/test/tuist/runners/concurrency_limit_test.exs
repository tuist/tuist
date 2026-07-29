defmodule Tuist.Runners.ConcurrencyLimitTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Runners.ConcurrencyLimit

  test "changeset requires a positive platform resource budget" do
    account = account_fixture()

    changeset =
      ConcurrencyLimit.changeset(%ConcurrencyLimit{}, %{
        account_id: account.id,
        platform: :linux,
        vcpus: 0,
        memory_gb: -1
      })

    refute changeset.valid?
    assert "must be greater than 0" in errors_on(changeset).vcpus
    assert "must be greater than 0" in errors_on(changeset).memory_gb
  end

  test "changeset accepts a valid platform resource budget" do
    account = account_fixture()

    changeset =
      ConcurrencyLimit.changeset(%ConcurrencyLimit{}, %{
        account_id: account.id,
        platform: :macos,
        vcpus: 12,
        memory_gb: 28
      })

    assert changeset.valid?
  end
end
