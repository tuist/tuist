defmodule Tuist.SubscriptionTest do
  use TuistTestSupport.Cases.DataCase

  alias Tuist.Accounts
  alias Tuist.Billing.Subscription
  alias TuistTestSupport.Fixtures.AccountsFixtures

  describe "create_changeset/2" do
    test "plan is required" do
      changeset =
        Subscription.create_changeset(%Subscription{}, %{
          subscription_id: "subscription_id",
          status: "active",
          account_id: 1,
          default_payment_method: "default_payment_method"
        })

      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).plan
    end

    test "subscription_id is required" do
      changeset =
        Subscription.create_changeset(%Subscription{}, %{
          plan: :pro,
          status: "active",
          account_id: 1,
          default_payment_method: "default_payment_method"
        })

      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).subscription_id
    end

    test "status is required" do
      changeset =
        Subscription.create_changeset(%Subscription{}, %{
          plan: :pro,
          subscription_id: "subscription_id",
          account_id: 1,
          default_payment_method: "default_payment_method"
        })

      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).status
    end

    test "account_id is required" do
      changeset =
        Subscription.create_changeset(%Subscription{}, %{
          plan: :pro,
          subscription_id: "subscription_id",
          status: "active",
          default_payment_method: "default_payment_method"
        })

      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).account_id
    end

    test "default_payment_method is not required" do
      changeset =
        Subscription.create_changeset(%Subscription{}, %{
          plan: :pro,
          subscription_id: "subscription_id",
          status: "active",
          account_id: 1
        })

      assert changeset.valid? == true
    end

    test "subscription_id is unique" do
      subscription_id = "#{unique_integer()}"

      organization = AccountsFixtures.organization_fixture()
      account = Accounts.get_account_from_organization(organization)

      changeset =
        Subscription.create_changeset(%Subscription{}, %{
          plan: :pro,
          subscription_id: subscription_id,
          status: "active",
          account_id: account.id,
          default_payment_method: "default_payment_method"
        })

      # When
      {:ok, _} = Repo.insert(changeset)
      {:error, got} = Repo.insert(changeset)

      # Then
      assert "has already been taken" in errors_on(got).subscription_id
    end

    test "when the plan is invalid" do
      changeset =
        Subscription.create_changeset(%Subscription{}, %{
          plan: :none,
          subscription_id: "subscription_id",
          status: "active",
          account_id: 1,
          default_payment_method: "default_payment_method"
        })

      assert changeset.valid? == false
      assert "is invalid" in errors_on(changeset).plan
    end

    test "when the plan is valid" do
      for plan <- [:enterprise, :air, :pro] do
        changeset =
          Subscription.create_changeset(%Subscription{}, %{
            plan: plan,
            subscription_id: "subscription_id",
            status: "active",
            account_id: 1,
            default_payment_method: "default_payment_method"
          })

        assert Map.get(errors_on(changeset), :plan) == nil
      end
    end
  end

  describe "update_changeset/2" do
    test "when the plan is valid on update" do
      for plan <- [:enterprise, :air, :pro] do
        changeset =
          Subscription.update_changeset(%Subscription{}, %{
            plan: plan,
            subscription_id: "subscription_id",
            status: "active",
            account_id: 1,
            default_payment_method: "default_payment_method"
          })

        assert Map.get(errors_on(changeset), :plan) == nil
      end
    end

    test "when the plan is invalid on update" do
      changeset =
        Subscription.update_changeset(%Subscription{}, %{
          plan: :none
        })

      assert changeset.valid? == false
      assert "is invalid" in errors_on(changeset).plan
    end
  end
end
