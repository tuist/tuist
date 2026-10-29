defmodule Atlas.Finance.FinancingTest do
  use Atlas.DataCase, async: true

  import Atlas.FinancingsFixtures

  alias Atlas.Finance.Financing

  describe "create_changeset/2" do
    test "accepts a loan with a principal amount" do
      changeset = Financing.create_changeset(%Financing{}, loan_attrs())

      assert changeset.valid?
      assert get_field(changeset, :type) == "loan"
      assert get_field(changeset, :accounting_treatment) == "undetermined"
      assert get_field(changeset, :status) == "active"
    end

    test "accepts a lease with a purchase option" do
      changeset = Financing.create_changeset(%Financing{}, lease_with_option_attrs())

      assert changeset.valid?
      assert get_field(changeset, :purchase_option_amount)
    end

    test "stores the supplier separately from the financing provider" do
      changeset =
        Financing.create_changeset(
          %Financing{},
          lease_with_option_attrs(%{provider: "Targo", supplier: "Apple"})
        )

      assert changeset.valid?
      assert get_field(changeset, :provider) == "Targo"
      assert get_field(changeset, :supplier) == "Apple"
    end

    test "rejects a loan without principal_amount" do
      attrs = loan_attrs() |> Map.delete(:principal_amount)
      changeset = Financing.create_changeset(%Financing{}, attrs)

      assert %{principal_amount: [msg | _]} = errors_on(changeset)
      assert msg =~ "required for loans"
    end

    test "rejects a lease with principal_amount" do
      attrs = lease_with_option_attrs() |> Map.put(:principal_amount, Decimal.new("500.00"))
      changeset = Financing.create_changeset(%Financing{}, attrs)

      assert %{principal_amount: [msg | _]} = errors_on(changeset)
      assert msg =~ "must be null for leases"
    end

    test "rejects a purchase option on the wrong type" do
      attrs =
        loan_attrs()
        |> Map.put(:purchase_option_amount, Decimal.new("100.00"))

      changeset = Financing.create_changeset(%Financing{}, attrs)
      assert %{purchase_option_amount: [msg | _]} = errors_on(changeset)
      assert msg =~ "lease_with_purchase_option"
    end

    test "requires provider, commencement date, and currency" do
      changeset = Financing.create_changeset(%Financing{}, %{type: "loan"})

      required = [:provider, :disbursement_or_commencement_on, :currency]

      for field <- required do
        assert %{^field => ["can't be blank"]} = errors_on(changeset)
      end
    end

    test "rejects an unknown currency" do
      changeset = Financing.create_changeset(%Financing{}, loan_attrs(%{currency: "XYZ"}))
      assert %{currency: [msg | _]} = errors_on(changeset)
      assert msg =~ "ISO 4217"
    end

    test "rejects an unknown accounting treatment" do
      changeset =
        Financing.create_changeset(
          %Financing{},
          loan_attrs(%{accounting_treatment: "bogus"})
        )

      assert %{accounting_treatment: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "database constraints" do
    test "inserts a loan and a lease successfully" do
      assert %Financing{} = insert_financing!(%{type: "loan"})
      assert %Financing{} = insert_financing!(%{type: "lease_with_purchase_option"})
    end
  end
end
