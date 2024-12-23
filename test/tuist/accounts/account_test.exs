defmodule Tuist.AccountTest do
  alias Tuist.Accounts.Account
  use TuistTestSupport.Cases.DataCase
  use Mimic

  test "account is created when customer_id is present and billing is enabled" do
    # Given
    changeset =
      Account.create_changeset(%Account{}, %{
        name: "Test",
        user_id: 1,
        customer_id: "cus_123"
      })

    assert changeset.valid? == true
  end

  test "name cannot contain dots" do
    changeset =
      Account.create_changeset(%Account{}, %{name: "my.name", user_id: 1})

    assert changeset.valid? == false
    assert "can't contain a dot" in errors_on(changeset).name
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
        Account.create_changeset(%Account{}, %{name: "Test", user_id: 1, customer_id: "cus_123"})

      assert changeset.valid? == true
    end

    test "changeset is valid when organization_id is present" do
      changeset =
        Account.create_changeset(%Account{}, %{
          name: "Test",
          organization_id: 1,
          customer_id: "cus_123"
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
end
