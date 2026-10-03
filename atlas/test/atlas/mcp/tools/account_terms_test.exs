defmodule Atlas.MCP.Tools.AccountTermsTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Accounts
  alias Atlas.Accounts.Term
  alias Atlas.MCP.Tools.CreateAccountTerm
  alias Atlas.MCP.Tools.DeleteAccountTerm
  alias Atlas.MCP.Tools.ListAccountTerms
  alias Atlas.MCP.Tools.UpdateAccountTerm

  defp insert_term!(account, attrs) do
    {:ok, term} = Accounts.create_term(account, attrs)
    term
  end

  describe "create_account_term" do
    test "creates a term for the account, defaulting source to atlas" do
      account = insert_account!(%{})

      {:ok, payload} =
        execute_tool(CreateAccountTerm, nil, %{
          "account_id" => account.id,
          "payment" => "yearly",
          "start_date" => "2025-09-01",
          "end_date" => "2026-09-01",
          "seats" => 14,
          "price_per_seat" => "40",
          "total" => "6720",
          "currency" => "EUR",
          "po_number" => "PO-1"
        })

      assert payload.payment == "yearly"
      assert payload.start_date == "2025-09-01"
      assert payload.end_date == "2026-09-01"
      assert payload.seats == 14
      assert payload.total == "6720"
      assert payload.po_number == "PO-1"

      term = Repo.get!(Term, payload.id)
      assert term.account_id == account.id
      assert term.source == "atlas"
    end

    test "accepts numeric amounts" do
      account = insert_account!(%{})

      {:ok, payload} =
        execute_tool(CreateAccountTerm, nil, %{
          "account_id" => account.id,
          "payment" => "monthly",
          "start_date" => "2025-01-01",
          "total" => 4800
        })

      assert payload.total == "4800"
    end

    test "returns a validation error when required fields are missing" do
      account = insert_account!(%{})

      assert {:error, message} =
               execute_tool(CreateAccountTerm, nil, %{"account_id" => account.id, "payment" => "yearly"})

      assert message =~ "total"
    end

    test "errors when the account cannot be resolved" do
      assert {:error, _} =
               execute_tool(CreateAccountTerm, nil, %{
                 "payment" => "yearly",
                 "start_date" => "2025-09-01",
                 "total" => "10"
               })
    end
  end

  describe "list_account_terms" do
    test "returns terms most recent first" do
      account = insert_account!(%{})

      insert_term!(account, %{
        "payment" => "yearly",
        "start_date" => "2024-01-01",
        "total" => "1000"
      })

      insert_term!(account, %{
        "payment" => "yearly",
        "start_date" => "2026-01-01",
        "total" => "2000"
      })

      {:ok, payload} = execute_tool(ListAccountTerms, nil, %{"account_id" => account.id})

      assert payload.count == 2
      assert [latest, previous] = payload.terms
      assert latest.start_date == "2026-01-01"
      assert previous.start_date == "2024-01-01"
    end
  end

  describe "update_account_term" do
    test "updates fields on an existing term" do
      account = insert_account!(%{})

      term =
        insert_term!(account, %{
          "payment" => "yearly",
          "start_date" => "2025-09-01",
          "total" => "6720",
          "seats" => 14
        })

      {:ok, payload} =
        execute_tool(UpdateAccountTerm, nil, %{"term_id" => term.id, "seats" => 20, "po_number" => "PO-9"})

      assert payload.seats == 20
      assert payload.po_number == "PO-9"

      reloaded = Repo.get!(Term, term.id)
      assert reloaded.seats == 20
      # Untouched fields are preserved.
      assert reloaded.source == "atlas"
      assert Decimal.equal?(reloaded.total, Decimal.new("6720"))
    end

    test "errors when term_id is missing" do
      assert {:error, _} = execute_tool(UpdateAccountTerm, nil, %{"seats" => 1})
    end

    test "errors when the term is missing" do
      assert {:error, _} =
               execute_tool(UpdateAccountTerm, nil, %{"term_id" => Ecto.UUID.generate(), "seats" => 1})
    end
  end

  describe "delete_account_term" do
    test "deletes an existing term" do
      account = insert_account!(%{})

      term =
        insert_term!(account, %{
          "payment" => "yearly",
          "start_date" => "2025-09-01",
          "total" => "6720"
        })

      {:ok, payload} = execute_tool(DeleteAccountTerm, nil, %{"term_id" => term.id})

      assert payload.deleted == true
      refute Repo.get(Term, term.id)
    end

    test "errors when the term is missing" do
      assert {:error, _} = execute_tool(DeleteAccountTerm, nil, %{"term_id" => Ecto.UUID.generate()})
    end
  end
end
