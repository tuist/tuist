defmodule Tuist.AccountTest do
  use TuistTestSupport.Cases.DataCase
  use Mimic

  alias Tuist.Accounts.Account
  alias Tuist.Accounts.User

  test "account is created when customer_id is present and billing is enabled" do
    # Given
    changeset =
      Account.create_changeset(%Account{}, %{
        name: "Test",
        user_id: 1,
        customer_id: "cus_123",
        billing_email: "#{UUIDv7.generate()}@tuist.dev"
      })

    assert changeset.valid? == true
  end

  test "name cannot contain dots" do
    changeset =
      Account.create_changeset(%Account{}, %{name: "my.name", user_id: 1})

    assert changeset.valid? == false
    assert "must contain only alphanumeric characters" in errors_on(changeset).name
  end

  describe "handle validity" do
    test "it fails the validation if a handle is included in the block list" do
      changeset =
        Account.create_changeset(%Account{}, %{
          name: Enum.random(Application.get_env(:tuist, :blocked_handles))
        })

      assert changeset.valid? == false
      assert "is reserved" in errors_on(changeset).name
    end
  end

  describe "user_id and organization_id validity" do
    test "changeset is valid when user_id is present" do
      changeset =
        Account.create_changeset(%Account{}, %{
          name: "Test",
          user_id: 1,
          customer_id: "cus_123",
          billing_email: "#{UUIDv7.generate()}@tuist.dev"
        })

      assert changeset.valid? == true
    end

    test "changeset is valid when organization_id is present" do
      changeset =
        Account.create_changeset(%Account{}, %{
          name: "Test",
          organization_id: 1,
          customer_id: "cus_123",
          billing_email: "#{UUIDv7.generate()}@tuist.dev"
        })

      assert changeset.valid? == true
    end

    test "only one of user_id or organization_id can be present" do
      changeset =
        Account.create_changeset(%Account{}, %{name: "Test", user_id: 1, organization_id: 1})

      assert changeset.valid? == false

      assert ["only one of user_id or organization_id can be present"] ==
               errors_on(changeset).organization_id

      assert ["only one of user_id or organization_id can be present"] ==
               errors_on(changeset).user_id
    end

    test "user_id or organization_id must be specified" do
      changeset =
        Account.create_changeset(%Account{}, %{name: "Test"})

      assert changeset.valid? == false
      assert ["can't be blank"] == errors_on(changeset).organization_id
    end
  end

  describe "update_changeset/2" do
    test "validates name format" do
      assert Account.update_changeset(%Account{}, %{name: "myname"}).valid?
      refute Account.update_changeset(%Account{}, %{name: "my.name"}).valid?
    end

    test "allows updating tenant_id" do
      changeset = Account.update_changeset(%Account{}, %{tenant_id: "tenant-123"})
      assert changeset.valid?
      assert changeset.changes.tenant_id == "tenant-123"
    end
  end

  describe "create_changeset/2" do
    test "valid name passes all validations" do
      changeset =
        Account.create_changeset(%Account{}, %{
          name: "valid-name123",
          user_id: 1,
          billing_email: "#{UUIDv7.generate()}@tuist.dev"
        })

      assert changeset.valid?
    end

    test "rejects names with invalid characters" do
      invalid_names = [
        # underscore not allowed
        "invalid_name",
        # space not allowed
        "invalid name",
        # special character not allowed
        "invalid!name",
        # special character not allowed
        "invalid@name",
        # period not allowed
        "invalid.name"
      ]

      for name <- invalid_names do
        changeset = Account.create_changeset(%Account{}, %{name: name, user_id: 1})
        assert "must contain only alphanumeric characters" in errors_on(changeset).name
      end
    end

    test "name is valid if it contains just one character" do
      changeset =
        Account.create_changeset(%Account{}, %{name: "a", user_id: 1, billing_email: "#{UUIDv7.generate()}@tuist.dev"})

      assert changeset.valid? == true
    end

    test "rejects names that are too long" do
      long_name = String.duplicate("a", 33)
      changeset = Account.create_changeset(%Account{}, %{name: long_name, user_id: 1})
      assert "should be at most 32 character(s)" in errors_on(changeset).name
    end

    test "validates tenant_id uniqueness on update" do
      {:ok, user1} = Tuist.Repo.insert(%User{email: "user1@test.com", token: "token-a"})
      {:ok, user2} = Tuist.Repo.insert(%User{email: "user2@test.com", token: "token-b"})

      {:ok, account1} =
        %Account{}
        |> Account.create_changeset(%{
          name: "account1",
          user_id: user1.id,
          billing_email: "#{UUIDv7.generate()}@tuist.dev"
        })
        |> Tuist.Repo.insert()

      {:ok, account2} =
        %Account{}
        |> Account.create_changeset(%{
          name: "account2",
          user_id: user2.id,
          billing_email: "#{UUIDv7.generate()}@tuist.dev"
        })
        |> Tuist.Repo.insert()

      Tuist.Repo.update(Account.update_changeset(account1, %{tenant_id: "tenant-123"}))
      changeset = Account.update_changeset(account2, %{tenant_id: "tenant-123"})
      {:error, changeset} = Tuist.Repo.update(changeset)
      assert "has already been taken" in errors_on(changeset).tenant_id
    end
  end
end
