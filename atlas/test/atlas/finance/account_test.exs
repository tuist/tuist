defmodule Atlas.Finance.AccountTest do
  use Atlas.DataCase, async: true

  import Atlas.FinanceFixtures

  alias Atlas.Finance.Account

  describe "schema" do
    test "sets defaults" do
      account = %Account{}

      assert account.main == false
      assert account.metadata == %{}
    end
  end

  describe "changeset/2" do
    test "requires source, provider, external id, and name" do
      changeset = Account.changeset(%Account{}, %{})

      refute changeset.valid?

      assert errors_on(changeset) == %{
               finance_source_id: ["can't be blank"],
               provider: ["can't be blank"],
               external_id: ["can't be blank"],
               name: ["can't be blank"]
             }
    end

    test "normalizes strings and currencies" do
      source = insert_finance_source!()

      changeset =
        Account.changeset(%Account{}, %{
          finance_source_id: source.id,
          provider: " qonto ",
          external_id: " account_123 ",
          name: " Operating ",
          account_type: " checking ",
          account_subtype: "   ",
          currency: " eur ",
          status: " active ",
          balance_currency: " usd ",
          available_balance_currency: " gbp "
        })

      assert changeset.valid?
      assert get_change(changeset, :provider) == "qonto"
      assert get_change(changeset, :external_id) == "account_123"
      assert get_change(changeset, :name) == "Operating"
      assert get_change(changeset, :account_type) == "checking"
      assert get_change(changeset, :account_subtype) == nil
      assert get_change(changeset, :currency) == "EUR"
      assert get_change(changeset, :status) == "active"
      assert get_change(changeset, :balance_currency) == "USD"
      assert get_change(changeset, :available_balance_currency) == "GBP"
    end

    test "enforces account external id uniqueness per source" do
      source = insert_finance_source!()
      _account = insert_finance_account!(source, %{external_id: "account_123"})

      assert {:error, changeset} =
               %Account{}
               |> Account.changeset(%{
                 finance_source_id: source.id,
                 provider: source.provider,
                 external_id: "account_123",
                 name: "Duplicate Account"
               })
               |> Repo.insert()

      assert "has already been taken" in errors_on(changeset).external_id
    end

    test "allows the same account external id for different sources" do
      first_source = insert_finance_source!()
      second_source = insert_finance_source!()

      _account = insert_finance_account!(first_source, %{external_id: "account_123"})

      assert {:ok, account} =
               %Account{}
               |> Account.changeset(%{
                 finance_source_id: second_source.id,
                 provider: second_source.provider,
                 external_id: "account_123",
                 name: "Other Source Account"
               })
               |> Repo.insert()

      assert account.finance_source_id == second_source.id
    end
  end

  describe "provider_label/1" do
    test "formats provider strings" do
      assert Account.provider_label("qonto") == "Qonto"
      assert Account.provider_label("mercury_treasury") == "Mercury treasury"
      assert Account.provider_label(%Account{provider: " mercury "}) == "Mercury"
    end
  end
end
