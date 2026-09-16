defmodule Atlas.MCP.Serializers.AccountsTest do
  use ExUnit.Case, async: true

  alias Atlas.Accounts.Contact
  alias Atlas.Accounts.Event
  alias Atlas.Accounts.Outcome
  alias Atlas.Accounts.OutcomeReview
  alias Atlas.MCP.Serializers.Accounts

  test "list_response/2 adds a count next to the named collection" do
    assert Accounts.list_response(:contacts, [%{id: 1}, %{id: 2}]) == %{
             contacts: [%{id: 1}, %{id: 2}],
             count: 2
           }
  end

  test "serializes common account resources consistently" do
    contact = %Contact{id: "contact-id", account_id: "account-id", full_name: "Ada", email: "ada@example.com"}
    event = %Event{id: "event-id", source: "atlas", kind: "note", title: "Note", occurred_at: ~U[2026-05-01 00:00:00Z]}

    review = %OutcomeReview{
      id: "review-id",
      health: "at_risk",
      summary: "Approval is delayed",
      reviewed_at: ~U[2026-05-02 00:00:00Z]
    }

    outcome = %Outcome{
      id: "outcome-id",
      account_id: "account-id",
      title: "Complete security evaluation",
      status: "active",
      health: "at_risk",
      motion: "evaluation",
      reviews: [review]
    }

    assert Accounts.contact(contact).account_id == "account-id"
    assert Accounts.event(event).occurred_at == "2026-05-01T00:00:00Z"
    assert Accounts.outcome(outcome).reviews |> hd() |> Map.fetch!(:reviewed_at) == "2026-05-02T00:00:00Z"
  end
end
