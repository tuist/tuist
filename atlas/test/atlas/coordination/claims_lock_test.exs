defmodule Atlas.Coordination.ClaimsLockTest do
  @moduledoc """
  Covers the `FOR UPDATE` serialization in `Atlas.Coordination.Claims.create/4`.

  Observing one caller block on another's row lock needs two real database
  connections, which the SQL sandbox cannot provide: inside a sandbox every
  process shares one connection and one transaction, so the second caller would
  never see the first caller's lock. This test therefore runs unboxed against
  committed rows, which is also why it is the one module in the suite that must
  stay `async: false`. ExUnit runs synchronous modules after every asynchronous
  one, so the rows it commits are never visible to another test.
  """

  # credo:disable-for-next-line Credo.Check.Warning.AsyncTests
  use Atlas.DataCase, async: false

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Event
  alias Atlas.Accounts.Term
  alias Atlas.Audit.Activity
  alias Atlas.Coordination.Claims
  alias Atlas.Coordination.CrossDomainClaim
  alias Atlas.Evidence.Link
  alias Ecto.Adapters.SQL.Sandbox

  test "waits for the account lock before creating a first claim version" do
    {account, event, term} =
      Sandbox.unboxed_run(Repo, fn ->
        account = insert_account!()
        {account, insert_event!(account), insert_term!(account)}
      end)

    evidence = exact_evidence(event, term)
    attrs = claim_attrs("Renewal needs one coordinated recovery conversation")
    test_process = self()

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        claim_ids =
          CrossDomainClaim
          |> where([claim], claim.subject_account_id == ^account.id)
          |> select([claim], claim.id)
          |> Repo.all()

        Link
        |> where(
          [link],
          link.subject_id in ^claim_ids or link.record_id in ^[event.id, term.id]
        )
        |> Repo.delete_all()

        Activity
        |> where([activity], activity.target_id in ^claim_ids)
        |> Repo.delete_all()

        CrossDomainClaim
        |> where([claim], claim.subject_account_id == ^account.id)
        |> Repo.delete_all()

        Event
        |> where([stored_event], stored_event.id == ^event.id)
        |> Repo.delete_all()

        Term
        |> where([stored_term], stored_term.id == ^term.id)
        |> Repo.delete_all()

        Account
        |> where([stored_account], stored_account.id == ^account.id)
        |> Repo.delete_all()
      end)
    end)

    locker =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          Repo.transaction(fn ->
            Account
            |> where([stored_account], stored_account.id == ^account.id)
            |> lock("FOR UPDATE")
            |> Repo.one!()

            send(test_process, {:account_locked, self()})

            receive do
              :release_account -> :released
            end
          end)
        end)
      end)

    assert_receive {:account_locked, locker_process}

    claimant =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          send(test_process, :claim_started)
          result = Claims.create(account, attrs, evidence)
          send(test_process, {:claim_finished, result})
          result
        end)
      end)

    assert_receive :claim_started
    refute_receive {:claim_finished, _result}, 100
    send(locker_process, :release_account)

    assert {:ok, :released} = Task.await(locker, 5_000)
    assert {:ok, claim} = Task.await(claimant, 5_000)
    assert claim.version == 1
    assert Repo.aggregate(from(claim in CrossDomainClaim, where: claim.subject_account_id == ^account.id), :count) == 1
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
