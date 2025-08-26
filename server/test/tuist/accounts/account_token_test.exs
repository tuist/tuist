defmodule Tuist.Accounts.AccountTokenTest do
  use TuistTestSupport.Cases.DataCase

  alias Tuist.Accounts.AccountToken
  alias TuistTestSupport.Fixtures.AccountsFixtures

  describe "create_changeset/1" do
    test "ensures an account_id is present" do
      # Given
      token = %AccountToken{}

      # When
      got = AccountToken.create_changeset(token, %{encrypted_token_hash: "hash"})

      # Then
      assert "can't be blank" in errors_on(got).account_id
    end

    test "ensure an encrypted_token_hash is present" do
      # Given
      token = %AccountToken{}

      # When
      got = AccountToken.create_changeset(token, %{account_id: 1})

      # Then
      assert "can't be blank" in errors_on(got).encrypted_token_hash
    end

    test "ensure scopes are present" do
      # Given
      token = %AccountToken{}

      # When
      got = AccountToken.create_changeset(token, %{})

      # Then
      assert "can't be blank" in errors_on(got).scopes
    end

    test "ensure scopes are valid" do
      # Given
      token = %AccountToken{}

      # When
      got = AccountToken.create_changeset(token, %{scopes: [:invalid_scope]})

      # Then
      assert "is invalid" in errors_on(got).scopes
    end

    test "is valid when contains all necessary attributes" do
      # Given
      token = %AccountToken{}

      # When
      got =
        AccountToken.create_changeset(token, %{
          account_id: 1,
          encrypted_token_hash: "hash",
          scopes: [:registry_read]
        })

      # Then
      assert got.valid?
    end

    test "ensures account_id and encrypted_token_hash are unique" do
      # Given
      token = %AccountToken{}
      account_id = AccountsFixtures.user_fixture(preload: [:account]).account.id

      changeset =
        AccountToken.create_changeset(token, %{
          account_id: account_id,
          encrypted_token_hash: "hash",
          scopes: []
        })

      Repo.insert!(changeset)

      # When
      {:error, got} =
        Repo.insert(
          AccountToken.create_changeset(token, %{
            account_id: account_id,
            encrypted_token_hash: "hash",
            scopes: []
          })
        )

      # Then
      assert "has already been taken" in errors_on(got).account_id
    end
  end
end
