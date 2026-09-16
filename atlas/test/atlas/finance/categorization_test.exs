defmodule Atlas.Finance.CategorizationTest do
  use Atlas.DataCase, async: true

  import Atlas.FinanceFixtures

  alias Atlas.Audit.Activity
  alias Atlas.Finance.Categorization
  alias Atlas.Repo

  test "creates broad categories with normalized slugs" do
    assert {:ok, category} =
             Categorization.create_category(%{
               "name" => "Cloud Infrastructure",
               "description" => "Cloud hosting and infrastructure services",
               "direction" => "debit"
             })

    assert category.name == "Cloud Infrastructure"
    assert category.slug == "cloud-infrastructure"
    assert category.direction == "debit"
    assert Repo.get_by!(Activity, action: "finance_category.upserted", target_id: category.id)
  end

  test "rejects categories that are too specific to one transaction" do
    source = insert_finance_source!()
    account = insert_finance_account!(source)
    transaction = insert_finance_transaction!(account, %{counterparty_name: "OpenAI"})

    assert {:error, :category_too_specific} =
             Categorization.create_category(%{"name" => "OpenAI"}, transactions: [transaction])
  end

  test "categorizes transactions with category metadata" do
    source = insert_finance_source!()
    account = insert_finance_account!(source)
    category = insert_finance_category!(%{name: "Payroll", direction: "debit"})
    transaction = insert_finance_transaction!(account, %{direction: "debit"})

    assert {:ok, updated} =
             Categorization.categorize_transaction(transaction.id, category.id, %{
               "confidence" => 0.92,
               "reason" => "Payroll provider"
             })

    assert updated.finance_category_id == category.id
    assert Decimal.equal?(updated.categorization_confidence, Decimal.new("0.92"))
    assert updated.categorization_reason == "Payroll provider"
    assert updated.categorized_by_agent == "finance_transaction_categorization_agent"
    assert updated.categorized_at

    activity = Repo.get_by!(Activity, action: "finance_transaction.categorized", target_id: updated.id)
    assert activity.metadata["category_id"] == category.id

    assert Repo.preload(updated, :category).category.name == "Payroll"
  end

  test "rejects category direction mismatches" do
    source = insert_finance_source!()
    account = insert_finance_account!(source)
    category = insert_finance_category!(%{name: "Revenue", direction: "credit"})
    transaction = insert_finance_transaction!(account, %{direction: "debit"})

    assert {:error, :category_direction_mismatch} =
             Categorization.categorize_transaction(transaction.id, category.id)
  end
end
