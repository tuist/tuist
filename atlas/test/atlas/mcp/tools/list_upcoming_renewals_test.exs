defmodule Atlas.MCP.Tools.ListUpcomingRenewalsTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Accounts.Term
  alias Atlas.MCP.Tools.ListUpcomingRenewals

  test "returns active customer renewals nearest first" do
    first_renewal = Date.utc_today() |> Date.add(15)
    second_renewal = Date.utc_today() |> Date.add(45)

    first =
      insert_account!(%{
        account_key: "customer:first-upcoming-renewal",
        name: "First Upcoming Renewal",
        primary_domain: "first.example",
        segment: :customer,
        status: "active",
        currency: "EUR",
        current_value: Decimal.new("0.00"),
        next_renewal_date: first_renewal
      })

    %Term{account_id: first.id}
    |> Term.changeset(%{
      source: "atlas",
      payment: "yearly",
      start_date: Date.add(Date.utc_today(), -335),
      end_date: first_renewal,
      total: Decimal.new("12000.00"),
      currency: "EUR"
    })
    |> Repo.insert!()

    second =
      insert_account!(%{
        account_key: "customer:second-upcoming-renewal",
        name: "Second Upcoming Renewal",
        segment: :customer,
        status: "active",
        currency: "USD",
        current_value: Decimal.new("24000.00"),
        next_renewal_date: second_renewal
      })

    _past =
      insert_account!(%{
        account_key: "customer:past-upcoming-renewal",
        name: "Past Renewal",
        segment: :customer,
        status: "active",
        next_renewal_date: Date.add(Date.utc_today(), -1)
      })

    _prospect =
      insert_account!(%{
        account_key: "prospect:upcoming-renewal",
        name: "Prospect Renewal",
        segment: :prospect,
        next_renewal_date: first_renewal
      })

    {:ok, payload} = execute_tool(ListUpcomingRenewals, nil, %{})

    assert payload.count == 2
    assert Enum.map(payload.renewals, & &1.id) == [first.id, second.id]

    assert %{
             account_key: "customer:first-upcoming-renewal",
             name: "First Upcoming Renewal",
             primary_domain: "first.example",
             status: "active",
             currency: "EUR",
             current_value: "12000.00",
             next_renewal_date: first_renewal_iso
           } = hd(payload.renewals)

    assert first_renewal_iso == Date.to_iso8601(first_renewal)
  end

  test "respects page_size" do
    first_renewal = Date.utc_today() |> Date.add(15)
    second_renewal = Date.utc_today() |> Date.add(45)

    first =
      insert_account!(%{
        account_key: "customer:first-limited-renewal",
        name: "First Limited Renewal",
        segment: :customer,
        status: "active",
        next_renewal_date: first_renewal
      })

    _second =
      insert_account!(%{
        account_key: "customer:second-limited-renewal",
        name: "Second Limited Renewal",
        segment: :customer,
        status: "active",
        next_renewal_date: second_renewal
      })

    {:ok, payload} = execute_tool(ListUpcomingRenewals, nil, %{"page_size" => 1})

    assert payload.count == 1
    assert [%{id: first_id}] = payload.renewals
    assert first_id == first.id
  end
end
