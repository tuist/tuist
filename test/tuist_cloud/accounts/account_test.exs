defmodule TuistCloud.AccountTest do
  alias TuistCloud.Accounts.Account
  alias TuistCloud.Billing
  use TuistCloud.DataCase
  use Mimic

  test "customer_id is required when billing is enabled" do
    # Given
    Billing
    |> stub(:enabled?, fn -> true end)

    changeset =
      Account.create_changeset(%Account{}, %{name: "Test", user_id: 1})

    assert changeset.valid? == false
    assert "can't be blank" in errors_on(changeset).customer_id
  end

  test "account is created when customer_id is present and billing is enabled" do
    # Given
    Billing
    |> stub(:enabled?, fn -> true end)

    changeset =
      Account.create_changeset(%Account{}, %{
        name: "Test",
        user_id: 1,
        customer_id: "cus_123"
      })

    assert changeset.valid? == true
  end

  test "customer_id is not required when billing is not enabled" do
    # Given
    Billing
    |> stub(:enabled?, fn -> false end)

    changeset =
      Account.create_changeset(%Account{}, %{name: "Test", user_id: 1})

    assert changeset.valid? == true
  end

  test "name cannot contain dots" do
    changeset =
      Account.create_changeset(%Account{}, %{name: "my.name", user_id: 1})

    assert changeset.valid? == false
    assert "can't contain a dot" in errors_on(changeset).name
  end

  describe "user_id and organization_id validity" do
    test "changeset is valid when user_id is present" do
      changeset =
        Account.create_changeset(%Account{}, %{name: "Test", user_id: 1})

      assert changeset.valid? == true
    end

    test "changeset is valid when organization_id is present" do
      changeset =
        Account.create_changeset(%Account{}, %{name: "Test", organization_id: 1})

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

  describe "plan validity" do
    test "when the plan is invalid" do
      changeset =
        Account.create_changeset(%Account{}, %{plan: :invalid})

      assert changeset.valid? == false
      assert "is invalid" in errors_on(changeset).plan
    end

    test "when the plan is valid" do
      for plan <- [:none, :enterprise, :indie, :pro] do
        changeset =
          Account.create_changeset(%Account{}, %{plan: plan})

        assert Map.get(errors_on(changeset), :plan) == nil
      end
    end
  end
end
