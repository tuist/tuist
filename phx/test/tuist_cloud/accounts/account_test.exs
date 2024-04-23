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
      Account.create_changeset(%Account{}, %{name: "Test", owner_type: "User", owner_id: 1})

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
        owner_type: "User",
        owner_id: 1,
        customer_id: "cus_123"
      })

    assert changeset.valid? == true
  end

  test "customer_id is not required when billing is not enabled" do
    # Given
    Billing
    |> stub(:enabled?, fn -> false end)

    changeset =
      Account.create_changeset(%Account{}, %{name: "Test", owner_type: "User", owner_id: 1})

    assert changeset.valid? == true
  end
end
