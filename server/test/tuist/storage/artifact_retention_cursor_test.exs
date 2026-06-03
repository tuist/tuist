defmodule Tuist.Storage.ArtifactRetentionCursorTest do
  use TuistTestSupport.Cases.DataCase

  alias Tuist.Repo
  alias Tuist.Storage.ArtifactRetentionCursor
  alias TuistTestSupport.Fixtures.AccountsFixtures

  describe "changeset/2" do
    test "is valid with all required fields" do
      account = AccountsFixtures.account_fixture()

      changeset =
        ArtifactRetentionCursor.changeset(%ArtifactRetentionCursor{}, %{
          account_id: account.id,
          artifact_type: :preview_app_build,
          after_inserted_at: DateTime.utc_now(),
          after_id: "cursor-id"
        })

      assert changeset.valid?
    end

    test "requires account, artifact type, inserted_at cursor, and id cursor" do
      changeset = ArtifactRetentionCursor.changeset(%ArtifactRetentionCursor{}, %{})

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).account_id
      assert "can't be blank" in errors_on(changeset).artifact_type
      assert "can't be blank" in errors_on(changeset).after_inserted_at
      assert "can't be blank" in errors_on(changeset).after_id
    end

    test "requires a known artifact type" do
      account = AccountsFixtures.account_fixture()

      changeset =
        ArtifactRetentionCursor.changeset(%ArtifactRetentionCursor{}, %{
          account_id: account.id,
          artifact_type: :unknown,
          after_inserted_at: DateTime.utc_now(),
          after_id: "cursor-id"
        })

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).artifact_type
    end

    test "validates the account foreign key" do
      changeset =
        ArtifactRetentionCursor.changeset(%ArtifactRetentionCursor{}, %{
          account_id: 0,
          artifact_type: :preview_app_build,
          after_inserted_at: DateTime.utc_now(),
          after_id: "cursor-id"
        })

      assert {:error, changeset} = Repo.insert(changeset)
      assert "does not exist" in errors_on(changeset).account_id
    end

    test "validates uniqueness by account and artifact type" do
      account = AccountsFixtures.account_fixture()

      attrs = %{
        account_id: account.id,
        artifact_type: :preview_app_build,
        after_inserted_at: DateTime.utc_now(),
        after_id: "cursor-id"
      }

      assert {:ok, _cursor} =
               %ArtifactRetentionCursor{}
               |> ArtifactRetentionCursor.changeset(attrs)
               |> Repo.insert()

      assert {:error, changeset} =
               %ArtifactRetentionCursor{}
               |> ArtifactRetentionCursor.changeset(Map.put(attrs, :after_id, "next-cursor-id"))
               |> Repo.insert()

      assert "has already been taken" in errors_on(changeset).account_id
    end
  end
end
