defmodule Atlas.Coordination.ClaimsTest do
  use Atlas.DataCase, async: true

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Event
  alias Atlas.Accounts.Term
  alias Atlas.Coordination.Claims
  alias Atlas.Coordination.CrossDomainClaim
  alias Atlas.Evidence

  test "creates and versions a claim only from exact links to the same account" do
    account = insert_account!()
    event = insert_event!(account)
    term = insert_term!(account)
    evidence = exact_evidence(event, term)

    assert {:ok, first} = Claims.create(account, claim_attrs("Renewal needs a recovery conversation"), evidence)
    assert first.version == 1
    assert first.link_precision == "exact"
    assert first.domains == ["accounts", "finance"]
    assert length(Evidence.for_subject("cross_domain_claim", first.id)) == 2

    assert {:ok, second} = Claims.create(account, claim_attrs("Renewal recovery call is now due"), evidence)
    assert second.version == 2

    stored_first = Repo.get!(CrossDomainClaim, first.id)
    assert stored_first.superseded_by_id == second.id
    assert %DateTime{} = stored_first.valid_until
  end

  test "rejects a finance vendor record as customer account evidence" do
    account = insert_account!()
    event = insert_event!(account)

    evidence = [
      %{
        record_type: "account_event",
        record_id: event.id,
        source_class: "observed",
        observation: "Customer signal"
      },
      %{
        record_type: "finance_invoice",
        record_id: Ecto.UUID.generate(),
        source_class: "observed",
        observation: "Vendor invoice"
      }
    ]

    assert {:error, :exact_cross_domain_link_required} =
             Claims.create(account, claim_attrs("Vendor cost implies renewal risk"), evidence)
  end

  defp claim_attrs(statement) do
    %{
      claim_kind: "account_renewal_exposure",
      domains: ["accounts", "finance"],
      statement: statement,
      confidence: Decimal.new("0.90"),
      sensitivity: "internal",
      generated_by_agent: "renewal_exposure_detector"
    }
  end

  defp exact_evidence(event, term) do
    [
      %{
        record_type: "account_event",
        record_id: event.id,
        source_class: "observed",
        observation: "The customer requested a renewal conversation"
      },
      %{
        record_type: "account_term",
        record_id: term.id,
        source_class: "decided",
        observation: "The signed term ends soon"
      }
    ]
  end

  defp insert_account! do
    %Account{}
    |> Account.changeset(%{
      account_key: "account:#{System.unique_integer([:positive])}",
      name: "Northstar",
      segment: :customer
    })
    |> Repo.insert!()
  end

  defp insert_event!(account) do
    %Event{}
    |> Event.changeset(%{
      account_id: account.id,
      external_id: "event:#{System.unique_integer([:positive])}",
      source: "atlas",
      kind: "note",
      title: "Renewal signal",
      body: "Let us discuss the renewal",
      occurred_at: ~U[2026-07-20 10:00:00Z]
    })
    |> Repo.insert!()
  end

  defp insert_term!(account) do
    %Term{account_id: account.id}
    |> Term.changeset(%{
      source: "atlas",
      payment: "yearly",
      start_date: ~D[2025-09-01],
      end_date: ~D[2026-09-01],
      total: Decimal.new("12000"),
      currency: "EUR"
    })
    |> Repo.insert!()
  end
end
