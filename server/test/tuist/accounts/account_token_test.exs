defmodule Tuist.Accounts.AccountTokenTest do
  use TuistTestSupport.Cases.DataCase

  alias Tuist.Accounts.AccountToken
  alias TuistTestSupport.Fixtures.AccountsFixtures

  describe "create_changeset/1" do
    test "ensures an account_id is present" do
      # When
      got =
        AccountToken.create_changeset(%{
          encrypted_token_hash: "hash",
          scopes: ["project:cache:read"],
          name: "my-token"
        })

      # Then
      assert "can't be blank" in errors_on(got).account_id
    end

    test "ensures an encrypted_token_hash is present" do
      # When
      got =
        AccountToken.create_changeset(%{
          account_id: 1,
          scopes: ["project:cache:read"],
          name: "my-token"
        })

      # Then
      assert "can't be blank" in errors_on(got).encrypted_token_hash
    end

    test "ensures scopes are present" do
      # When
      got = AccountToken.create_changeset(%{name: "my-token"})

      # Then
      assert "can't be blank" in errors_on(got).scopes
    end

    test "ensures scopes are valid" do
      # When
      got =
        AccountToken.create_changeset(%{
          account_id: 1,
          encrypted_token_hash: "hash",
          scopes: ["invalid:scope"],
          name: "my-token"
        })

      # Then
      assert [error] = errors_on(got).scopes
      assert error =~ "contains invalid scopes"
    end

    test "ensures name is present" do
      # When
      got =
        AccountToken.create_changeset(%{
          account_id: 1,
          encrypted_token_hash: "hash",
          scopes: ["project:cache:read"]
        })

      # Then
      assert "can't be blank" in errors_on(got).name
    end

    test "ensures name contains only valid characters" do
      # When
      got =
        AccountToken.create_changeset(%{
          account_id: 1,
          encrypted_token_hash: "hash",
          scopes: ["project:cache:read"],
          name: "invalid name!"
        })

      # Then
      assert "must contain only alphanumeric characters, hyphens, and underscores" in errors_on(got).name
    end

    test "ensures name is not too long" do
      # When
      got =
        AccountToken.create_changeset(%{
          account_id: 1,
          encrypted_token_hash: "hash",
          scopes: ["project:cache:read"],
          name: String.duplicate("a", 33)
        })

      # Then
      assert "should be at most 32 character(s)" in errors_on(got).name
    end

    test "ensures name is not empty" do
      # When
      got =
        AccountToken.create_changeset(%{
          account_id: 1,
          encrypted_token_hash: "hash",
          scopes: ["project:cache:read"],
          name: ""
        })

      # Then
      assert "can't be blank" in errors_on(got).name
    end

    test "lowercases the name" do
      # When
      got =
        AccountToken.create_changeset(%{
          account_id: 1,
          encrypted_token_hash: "hash",
          scopes: ["project:cache:read"],
          name: "MY-TOKEN"
        })

      # Then
      assert Ecto.Changeset.get_change(got, :name) == "my-token"
    end

    test "allows valid names with hyphens and underscores" do
      # When
      got =
        AccountToken.create_changeset(%{
          account_id: 1,
          encrypted_token_hash: "hash",
          scopes: ["project:cache:read"],
          name: "my-token_123"
        })

      # Then
      refute Map.has_key?(errors_on(got), :name)
    end

    test "is valid when contains all necessary attributes" do
      # When
      got =
        AccountToken.create_changeset(%{
          account_id: 1,
          encrypted_token_hash: "hash",
          scopes: ["project:cache:read"],
          name: "my-token"
        })

      # Then
      assert got.valid?
    end

    test "accepts multiple valid scopes" do
      # When
      got =
        AccountToken.create_changeset(%{
          account_id: 1,
          encrypted_token_hash: "hash",
          scopes: ["project:cache:read", "project:cache:write", "account:registry:read"],
          name: "my-token"
        })

      # Then
      assert got.valid?
    end

    test "ensures account_id and encrypted_token_hash are unique" do
      # Given
      account_id = AccountsFixtures.user_fixture(preload: [:account]).account.id

      changeset =
        AccountToken.create_changeset(%{
          account_id: account_id,
          encrypted_token_hash: "hash",
          scopes: ["project:cache:read"],
          name: "token-1"
        })

      Repo.insert!(changeset)

      # When
      {:error, got} =
        Repo.insert(
          AccountToken.create_changeset(%{
            account_id: account_id,
            encrypted_token_hash: "hash",
            scopes: ["project:cache:read"],
            name: "token-2"
          })
        )

      # Then
      assert "has already been taken" in errors_on(got).account_id
    end

    test "ensures account_id and name are unique" do
      # Given
      account_id = AccountsFixtures.user_fixture(preload: [:account]).account.id

      changeset =
        AccountToken.create_changeset(%{
          account_id: account_id,
          encrypted_token_hash: "hash1",
          scopes: ["project:cache:read"],
          name: "my-token"
        })

      Repo.insert!(changeset)

      # When
      {:error, got} =
        Repo.insert(
          AccountToken.create_changeset(%{
            account_id: account_id,
            encrypted_token_hash: "hash2",
            scopes: ["project:cache:read"],
            name: "my-token"
          })
        )

      # Then - unique constraint error appears on first field of constraint
      errors = errors_on(got)

      assert "has already been taken" in Map.get(errors, :name, []) or
               "has already been taken" in Map.get(errors, :account_id, [])
    end

    test "validates expiration date is in the future" do
      # When
      got =
        AccountToken.create_changeset(%{
          account_id: 1,
          encrypted_token_hash: "hash",
          scopes: ["project:cache:read"],
          name: "my-token",
          expires_at: DateTime.add(DateTime.utc_now(), -1, :hour)
        })

      # Then
      assert "must be in the future" in errors_on(got).expires_at
    end

    test "accepts valid expiration date in the future" do
      # When
      got =
        AccountToken.create_changeset(%{
          account_id: 1,
          encrypted_token_hash: "hash",
          scopes: ["project:cache:read"],
          name: "my-token",
          expires_at: DateTime.add(DateTime.utc_now(), 1, :hour)
        })

      # Then
      refute Map.has_key?(errors_on(got), :expires_at)
    end
  end
end
