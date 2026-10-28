defmodule Atlas.Accounts.EventRoutingTest do
  use Atlas.DataCase, async: true

  alias Atlas.Accounts
  alias Atlas.Accounts.Account
  alias Atlas.Accounts.AccountHandle
  alias Atlas.Accounts.Contact
  alias Atlas.Accounts.EventRouting
  alias Atlas.Repo

  describe "find_account/1" do
    test "normalizes emails and matches by contact email" do
      account = insert_account!(%{primary_domain: "acme.example"})
      insert_contact!(account, %{email: "maya@acme.example"})

      assert %{account: ^account, matched_on: %{"type" => "contact_email", "value" => "maya@acme.example"}} =
               EventRouting.find_account([" Maya@Acme.EXAMPLE "])
    end

    test "ignores internal addresses before matching by domain" do
      _internal = insert_account!(%{primary_domain: "tuist.dev"})

      assert nil == EventRouting.find_account(["person@tuist.dev"])
    end

    test "returns flagged accounts only through find_non_account/1" do
      account = insert_account!(%{name: "Grafana Labs", primary_domain: "grafana.com"})
      assert {:ok, _account} = Accounts.mark_account_not_account(account, %{reason: "Vendor"})

      assert nil == EventRouting.find_account(["buyer@grafana.com"])

      assert %{
               account: %{id: account_id},
               matched_on: %{"type" => "primary_domain", "value" => "grafana.com"}
             } = EventRouting.find_non_account(["buyer@grafana.com"])

      assert account_id == account.id
    end
  end

  describe "upsert_contact/2" do
    test "skips blank and internal contact emails" do
      account = insert_account!(%{})

      assert {:ok, :skipped} = EventRouting.upsert_contact(account.id, %{"email" => "", "full_name" => "Blank"})

      assert {:ok, :skipped} =
               EventRouting.upsert_contact(account.id, %{"email" => "person@tuist.dev", "full_name" => "Internal"})

      assert EventRouting.list_account_contacts(account.id) == []
    end
  end

  describe "upsert_account/1" do
    test "creates a lead account with a Granola account key" do
      assert {:ok, account} =
               EventRouting.upsert_account(%{
                 "name" => "Northstar Retail",
                 "primary_domain" => "https://www.northstar.example/path",
                 "description" => "Evaluating Atlas after a Granola discovery call."
               })

      assert account.account_key == "granola:northstar-example"
      assert account.name == "Northstar Retail"
      assert account.primary_domain == "northstar.example"
      assert account.segment == :lead
      assert account.description == "Evaluating Atlas after a Granola discovery call."
    end

    test "updates an existing account by id" do
      account = insert_account!(%{name: "Northstar", segment: :lead})

      assert {:ok, updated} =
               EventRouting.upsert_account(%{
                 "account_id" => account.id,
                 "name" => "Northstar Retail",
                 "segment" => "prospect",
                 "primary_domain" => "northstar.example"
               })

      assert updated.id == account.id
      assert updated.name == "Northstar Retail"
      assert updated.segment == :prospect
      assert updated.primary_domain == "northstar.example"
    end

    test "updates an existing account by generated Granola key instead of duplicating it" do
      first =
        insert_account!(%{
          account_key: "granola:northstar-example",
          name: "Northstar",
          primary_domain: nil,
          segment: :lead
        })

      assert {:ok, second} =
               EventRouting.upsert_account(%{
                 "name" => "Northstar Retail",
                 "primary_domain" => "northstar.example",
                 "segment" => "prospect"
               })

      assert second.id == first.id
      assert second.name == "Northstar Retail"
      assert second.primary_domain == "northstar.example"
      assert Repo.aggregate(Account, :count) == 1
    end

    test "does not recreate accounts matching a flagged non-account domain or key" do
      account =
        insert_account!(%{
          account_key: "granola:grafana-com",
          name: "Grafana Labs",
          primary_domain: "grafana.com",
          segment: :lead
        })

      %AccountHandle{}
      |> AccountHandle.changeset(%{
        handle: "grafana.com",
        source: "domain",
        account_id: account.id
      })
      |> Repo.insert!()

      assert {:ok, _account} = Accounts.mark_account_not_account(account, %{reason: "Vendor"})

      assert {:error, :not_account} =
               EventRouting.upsert_account(%{
                 "name" => "Grafana Labs",
                 "primary_domain" => "grafana.com",
                 "segment" => "lead"
               })

      assert Repo.aggregate(Account, :count) == 1
    end
  end

  defp insert_account!(attrs) do
    defaults = %{
      account_key: "account:#{System.unique_integer([:positive])}",
      name: "Account",
      segment: :customer
    }

    %Account{}
    |> Account.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_contact!(account, attrs) do
    defaults = %{
      full_name: "Contact",
      email: "contact@example.com",
      account_id: account.id
    }

    %Contact{}
    |> Contact.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end
end
