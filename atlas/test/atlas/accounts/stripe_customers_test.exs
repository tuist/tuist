defmodule Atlas.Accounts.StripeCustomersTest do
  use Atlas.DataCase, async: true

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.StripeCustomers
  alias Atlas.Stripe
  alias Atlas.TestSupport.StripeClient

  describe "find_or_create_for_account/2" do
    test "returns :existing without calling Stripe when the account already has a customer id" do
      account = insert_account!(%{name: "Already Linked", stripe_customer_id: "cus_already"})

      StripeClient.put_search_customers(fn _args -> flunk("should not have searched") end)
      StripeClient.put_create_customer(fn _args -> flunk("should not have created") end)

      assert {:ok, %{status: :existing, account: returned, customer: nil}} =
               StripeCustomers.find_or_create_for_account(account)

      assert returned.id == account.id
    end

    test "matches a Stripe customer with the same name and persists the id" do
      account = insert_account!(%{name: "Acme Corp", primary_domain: "notion.so"})

      StripeClient.put_search_customers(fn {_query, _opts} ->
        {:ok,
         [
           %Stripe.Customer{id: "cus_notion", name: "Acme Corp, Inc.", email: "ap@notion.so"}
         ]}
      end)

      assert {:ok, %{status: :matched, account: updated, customer: customer}} =
               StripeCustomers.find_or_create_for_account(account)

      assert updated.stripe_customer_id == "cus_notion"
      assert customer.id == "cus_notion"
      assert Repo.get!(Account, account.id).stripe_customer_id == "cus_notion"
    end

    test "creates a Stripe customer when no candidate matches" do
      account =
        insert_account!(%{
          name: "Greenfield Co",
          legal_name: "Greenfield Co, Inc.",
          primary_domain: "greenfield.dev",
          description: "Series B fintech"
        })

      StripeClient.put_search_customers(fn {_query, _opts} ->
        {:ok, [%Stripe.Customer{id: "cus_other", name: "Completely Different Company"}]}
      end)

      test_pid = self()

      StripeClient.put_create_customer(fn {attrs, _opts} ->
        send(test_pid, {:created, attrs})

        {:ok,
         %Stripe.Customer{
           id: "cus_greenfield",
           name: attrs[:name],
           email: attrs[:email],
           description: attrs[:description]
         }}
      end)

      assert {:ok, %{status: :created, account: updated, customer: customer}} =
               StripeCustomers.find_or_create_for_account(account)

      assert updated.stripe_customer_id == "cus_greenfield"
      assert customer.id == "cus_greenfield"

      assert_received {:created, attrs}
      assert attrs[:name] == "Greenfield Co, Inc."
      assert attrs[:description] == "Series B fintech"
      assert attrs[:metadata]["atlas_account_id"] == account.id
      assert attrs[:metadata]["atlas_primary_domain"] == "greenfield.dev"
    end

    test "surfaces an ambiguous-candidates error when multiple customers tie within the window" do
      account = insert_account!(%{name: "Acme"})

      StripeClient.put_search_customers(fn {_query, _opts} ->
        {:ok,
         [
           %Stripe.Customer{id: "cus_a", name: "Acme"},
           %Stripe.Customer{id: "cus_b", name: "Acme"},
           %Stripe.Customer{id: "cus_c", name: "Acme, LLC"}
         ]}
      end)

      assert {:error, {:ambiguous_stripe_customer, candidates}} =
               StripeCustomers.find_or_create_for_account(account)

      assert length(candidates) >= 2
      assert Enum.all?(candidates, &match?(%Stripe.Customer{}, &1))
      refute Repo.get!(Account, account.id).stripe_customer_id
    end

    test "prefers the candidate whose email matches the account's primary domain" do
      account = insert_account!(%{name: "Acme Corp", primary_domain: "notion.so"})

      StripeClient.put_search_customers(fn {_query, _opts} ->
        {:ok,
         [
           %Stripe.Customer{id: "cus_namesake", name: "Acme Corp"},
           %Stripe.Customer{id: "cus_real", name: "Acme Corp", email: "billing@notion.so"}
         ]}
      end)

      assert {:ok, %{status: :matched, customer: %Stripe.Customer{id: "cus_real"}}} =
               StripeCustomers.find_or_create_for_account(account)
    end

    test "returns :stripe_disabled when no API key is configured" do
      account = insert_account!(%{name: "Disabled"})

      StripeClient.put_search_customers(:disabled)

      assert {:error, :stripe_disabled} = StripeCustomers.find_or_create_for_account(account)
    end
  end

  defp insert_account!(attrs) do
    defaults = %{
      account_key: "account:#{System.unique_integer([:positive])}",
      name: "Account",
      segment: :prospect
    }

    %Account{}
    |> Account.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end
end
