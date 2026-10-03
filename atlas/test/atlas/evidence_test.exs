defmodule Atlas.EvidenceTest do
  use Atlas.DataCase, async: true

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Event
  alias Atlas.Evidence
  alias Atlas.Finance.Invoice

  test "persists typed evidence, inherits sensitivity, and is idempotent" do
    event = insert_event!()
    subject_id = Ecto.UUID.generate()

    attrs = %{
      subject_type: "account_outcome_proposal",
      subject_id: subject_id,
      record_type: "account_event",
      record_id: event.id,
      source_class: "observed",
      sensitivity: "public",
      observation: "The customer asked for a rollout plan",
      position: 0
    }

    assert {:ok, first} = Evidence.link(attrs)
    assert first.sensitivity == "internal"
    assert first.occurred_at == event.occurred_at

    assert {:ok, duplicate} = Evidence.link(attrs)
    assert duplicate.id == first.id
    assert [stored] = Evidence.for_subject("account_outcome_proposal", subject_id)
    assert stored.id == first.id
  end

  test "does not allow unreviewed brief output to become evidence recursively" do
    assert {:error, :derived_content_is_not_evidence} =
             Evidence.link(%{
               subject_type: "cross_domain_claim",
               subject_id: Ecto.UUID.generate(),
               record_type: "brief_item",
               record_id: Ecto.UUID.generate(),
               source_class: "agent_derived",
               sensitivity: "internal",
               observation: "An agent inferred this from another agent summary",
               position: 0
             })
  end

  test "calculates candidate sensitivity from its most restricted evidence" do
    invoice =
      %Invoice{}
      |> Invoice.changeset(%{
        vendor_name: "Infrastructure Vendor",
        status: "extracted",
        extracted_at: ~U[2026-07-20 10:00:00Z]
      })
      |> Repo.insert!()

    assert {:ok, "restricted"} =
             Evidence.sensitivity_for(
               [
                 %{
                   record_type: "finance_invoice",
                   record_id: invoice.id,
                   source_class: "observed",
                   observation: "Restricted invoice evidence"
                 }
               ],
               "internal"
             )
  end

  defp insert_event! do
    account =
      %Account{}
      |> Account.changeset(%{
        account_key: "account:#{System.unique_integer([:positive])}",
        name: "Northstar",
        segment: :customer
      })
      |> Repo.insert!()

    %Event{}
    |> Event.changeset(%{
      account_id: account.id,
      external_id: "event:#{System.unique_integer([:positive])}",
      source: "atlas",
      kind: "note",
      title: "Customer signal",
      body: "Please send the rollout plan",
      occurred_at: ~U[2026-07-20 10:00:00Z]
    })
    |> Repo.insert!()
  end
end
