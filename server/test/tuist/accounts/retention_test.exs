defmodule Tuist.Accounts.RetentionTest do
  use ExUnit.Case, async: true

  alias Tuist.Accounts.Account

  test "defaults remain unset" do
    account = %Account{}
    assert account.artifact_retention_days == nil
    assert account.runner_log_retention_days == nil
  end

  test "accepts independent overrides and clears them with blank values" do
    changeset = Account.retention_changeset(%Account{}, %{artifact_retention_days: "7", runner_log_retention_days: "14"})
    assert changeset.valid?
    account = Ecto.Changeset.apply_changes(changeset)
    assert account.artifact_retention_days == 7
    assert account.runner_log_retention_days == 14

    cleared = Account.retention_changeset(account, %{artifact_retention_days: "", runner_log_retention_days: ""})
    assert cleared.valid?
    assert Ecto.Changeset.get_field(cleared, :artifact_retention_days) == nil
    assert Ecto.Changeset.get_field(cleared, :runner_log_retention_days) == nil
  end

  test "validates positive whole days within existing retention bounds" do
    for {field, maximum} <- [artifact_retention_days: 30, runner_log_retention_days: 90] do
      for invalid <- ["abc", "1.5", 0, -1, maximum + 1] do
        changeset = Account.retention_changeset(%Account{}, %{field => invalid})
        refute changeset.valid?
        assert Keyword.has_key?(changeset.errors, field)
      end

      assert Account.retention_changeset(%Account{}, %{field => 1}).valid?
      assert Account.retention_changeset(%Account{}, %{field => maximum}).valid?
    end
  end

  test "ordinary account updates cannot change retention" do
    changeset =
      Account.update_changeset(%Account{name: "acme"}, %{artifact_retention_days: 7, runner_log_retention_days: 14})

    refute Map.has_key?(changeset.changes, :artifact_retention_days)
    refute Map.has_key?(changeset.changes, :runner_log_retention_days)
  end
end
