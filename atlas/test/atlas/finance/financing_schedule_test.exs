defmodule Atlas.Finance.FinancingScheduleTest do
  use Atlas.DataCase, async: true

  import Atlas.FinancingsFixtures

  alias Atlas.Finance.FinancingSchedule
  alias Atlas.Repo

  setup do
    %{financing: insert_financing!()}
  end

  test "accepts a schedule row with known components", %{financing: financing} do
    assert %FinancingSchedule{} =
             insert_schedule!(financing, %{
               sequence: 1,
               expected_total: Decimal.new("1200.00"),
               principal_amount: Decimal.new("1000.00"),
               interest_amount: Decimal.new("200.00")
             })
  end

  test "rejects components exceeding expected_total via changeset", %{financing: financing} do
    changeset =
      FinancingSchedule.changeset(%FinancingSchedule{}, %{
        financing_id: financing.id,
        sequence: 1,
        due_on: ~D[2026-02-15],
        expected_total: Decimal.new("1000.00"),
        principal_amount: Decimal.new("900.00"),
        interest_amount: Decimal.new("200.00")
      })

    refute changeset.valid?
    assert errors_on(changeset)[:expected_total]
  end

  test "rejects duplicate sequence within a financing", %{financing: financing} do
    _ = insert_schedule!(financing, %{sequence: 42})

    {:error, changeset} =
      %FinancingSchedule{}
      |> FinancingSchedule.changeset(%{
        financing_id: financing.id,
        sequence: 42,
        due_on: ~D[2026-02-15],
        expected_total: Decimal.new("100.00")
      })
      |> Repo.insert()

    assert errors_on(changeset)[:financing_id] == ["has already been taken"]
  end
end
