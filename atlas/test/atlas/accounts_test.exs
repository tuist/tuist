defmodule Atlas.AccountsTest do
  use Atlas.DataCase, async: true

  alias Atlas.Accounts
  alias Atlas.Accounts.Account
  alias Atlas.Accounts.AccountHandle
  alias Atlas.Accounts.Contact
  alias Atlas.Accounts.Event
  alias Atlas.Accounts.Invoice
  alias Atlas.Accounts.Outcome
  alias Atlas.Accounts.Term
  alias Atlas.Audit.Activity
  alias Atlas.Licenses.Issuer
  alias Atlas.Licenses.License
  alias Atlas.Repo
  alias Atlas.Users.User

  describe "get_account_by_name/1" do
    test "returns an account by exact name, ignoring case" do
      account =
        insert_account!(%{
          account_key: "account:acme-labs",
          name: "Acme Labs",
          segment: :prospect
        })

      assert {:ok, found} = Accounts.get_account_by_name("acme labs")
      assert found.id == account.id
    end

    test "does not trim lookup names" do
      insert_account!(%{
        account_key: "account:acme-labs",
        name: "Acme Labs",
        segment: :prospect
      })

      assert {:error, :not_found} = Accounts.get_account_by_name(" Acme Labs ")
    end

    test "returns not_found when no account name matches" do
      assert {:error, :not_found} = Accounts.get_account_by_name("Missing")
      assert {:error, :not_found} = Accounts.get_account_by_name(" ")
    end
  end

  test "list_accounts filters by deal stage" do
    legal_review =
      insert_account!(%{
        account_key: "account:legal-review",
        name: "Legal Review",
        deal_stage: "legal_review"
      })

    discovery =
      insert_account!(%{
        account_key: "account:discovery",
        name: "Discovery",
        deal_stage: "discovery"
      })

    no_stage =
      insert_account!(%{
        account_key: "account:no-stage",
        name: "No Stage"
      })

    filtered_accounts =
      Accounts.list_accounts(filters: [%{id: "deal_stage", operator: :==, value: "legal_review"}])

    assert account_ids(filtered_accounts) == [legal_review.id]

    remaining_accounts =
      Accounts.list_accounts(filters: [%{id: "deal_stage", operator: :!=, value: "legal_review"}])

    assert MapSet.new(account_ids(remaining_accounts)) == MapSet.new([discovery.id, no_stage.id])
  end

  test "list_accounts sorts by the term-derived value rather than the stored one" do
    today = Date.utc_today()

    stale =
      insert_account!(%{
        account_key: "account:sort-stale",
        name: "Stale Value",
        segment: :customer,
        currency: "EUR",
        current_value: Decimal.new("0")
      })

    %Term{account_id: stale.id}
    |> Term.changeset(%{
      source: "atlas",
      payment: "yearly",
      start_date: Date.add(today, -30),
      end_date: Date.add(today, 335),
      total: Decimal.new("42000"),
      currency: "EUR"
    })
    |> Repo.insert!()

    stored =
      insert_account!(%{
        account_key: "account:sort-stored",
        name: "Stored Value",
        segment: :customer,
        currency: "EUR",
        current_value: Decimal.new("1200")
      })

    valueless =
      insert_account!(%{
        account_key: "account:sort-valueless",
        name: "No Value",
        segment: :customer,
        currency: "EUR",
        current_value: nil
      })

    descending = Accounts.list_accounts(sort_by: "value", sort_order: "desc")
    assert account_ids(descending) == [stale.id, stored.id, valueless.id]

    ascending = Accounts.list_accounts(sort_by: "value", sort_order: "asc")
    assert account_ids(ascending) == [stored.id, stale.id, valueless.id]
  end

  describe "contract_value/2" do
    test "keeps a stored value of zero distinct from a missing one" do
      zero =
        insert_account!(%{
          account_key: "account:zero-value",
          name: "Zero Value",
          segment: :customer,
          currency: "EUR",
          current_value: Decimal.new("0")
        })

      assert {value, "EUR"} = Accounts.contract_value(zero)
      assert Decimal.equal?(value, Decimal.new("0"))

      missing =
        insert_account!(%{
          account_key: "account:missing-value",
          name: "Missing Value",
          segment: :customer,
          currency: "EUR",
          current_value: nil
        })

      assert {nil, "EUR"} = Accounts.contract_value(missing)
    end

    test "prefers the nearest upcoming term when no term is active" do
      today = Date.utc_today()

      account =
        insert_account!(%{
          account_key: "account:upcoming-terms",
          name: "Upcoming Terms",
          segment: :customer,
          currency: "EUR",
          current_value: nil
        })

      for {start_offset, total} <- [{365, "24000"}, {30, "12000"}] do
        %Term{account_id: account.id}
        |> Term.changeset(%{
          source: "atlas",
          payment: "yearly",
          start_date: Date.add(today, start_offset),
          end_date: Date.add(today, start_offset + 364),
          total: Decimal.new(total),
          currency: "EUR"
        })
        |> Repo.insert!()
      end

      account = Repo.preload(account, :terms)

      assert {value, "EUR"} = Accounts.contract_value(account)
      assert Decimal.equal?(value, Decimal.new("12000"))
    end

    test "falls back to the most recently started term when every term has ended" do
      today = Date.utc_today()

      account =
        insert_account!(%{
          account_key: "account:ended-terms",
          name: "Ended Terms",
          segment: :customer,
          currency: "EUR",
          current_value: nil
        })

      for {start_offset, total} <- [{-800, "8000"}, {-400, "16000"}] do
        %Term{account_id: account.id}
        |> Term.changeset(%{
          source: "atlas",
          payment: "yearly",
          start_date: Date.add(today, start_offset),
          end_date: Date.add(today, start_offset + 364),
          total: Decimal.new(total),
          currency: "EUR"
        })
        |> Repo.insert!()
      end

      account = Repo.preload(account, :terms)

      assert {value, "EUR"} = Accounts.contract_value(account)
      assert Decimal.equal?(value, Decimal.new("16000"))
    end
  end

  describe "revenue_snapshot/1" do
    test "uses the latest account term when account current value is missing or stale" do
      term_only =
        insert_account!(%{
          account_key: "account:term-only-revenue",
          name: "Term Only Revenue",
          segment: :customer,
          currency: nil,
          current_value: nil
        })

      stale_value =
        insert_account!(%{
          account_key: "account:stale-revenue",
          name: "Stale Revenue",
          segment: :customer,
          currency: "EUR",
          current_value: Decimal.new("1200")
        })

      assert {:ok, _term} =
               Accounts.create_term(term_only, %{
                 payment: "yearly",
                 start_date: ~D[2026-01-01],
                 end_date: ~D[2026-12-31],
                 total: Decimal.new("12000"),
                 currency: "EUR"
               })

      assert {:ok, _term} =
               Accounts.create_term(stale_value, %{
                 payment: "yearly",
                 start_date: ~D[2026-01-01],
                 end_date: ~D[2026-12-31],
                 total: Decimal.new("24000"),
                 currency: "EUR"
               })

      snapshot = Accounts.revenue_snapshot()

      assert Decimal.equal?(snapshot.monthly_revenue_eur, Decimal.new("3000.00"))
      assert Decimal.equal?(snapshot.estimated_arr_eur, Decimal.new("36000.00"))
      assert snapshot.renewal_base_count == 2
    end
  end

  test "list_accounts filters accounts that need attention" do
    legal_review =
      insert_account!(%{
        account_key: "account:attention-legal",
        name: "Legal Review",
        deal_stage: "legal_review"
      })

    security_review =
      insert_account!(%{
        account_key: "account:attention-security",
        name: "Security Review",
        deal_stage: "security_review"
      })

    discovery =
      insert_account!(%{
        account_key: "account:attention-discovery",
        name: "Discovery",
        deal_stage: "discovery"
      })

    no_stage =
      insert_account!(%{
        account_key: "account:attention-none",
        name: "No Stage"
      })

    filtered_accounts =
      Accounts.list_accounts(filters: [%{id: "needs_attention", operator: :==, value: "true"}])

    assert MapSet.new(account_ids(filtered_accounts)) ==
             MapSet.new([legal_review.id, security_review.id])

    remaining_accounts =
      Accounts.list_accounts(filters: [%{id: "needs_attention", operator: :!=, value: "true"}])

    assert MapSet.new(account_ids(remaining_accounts)) == MapSet.new([discovery.id, no_stage.id])
  end

  describe "account parent relationships" do
    test "update_account/2 stores and preloads parent and child accounts" do
      parent = insert_account!(%{account_key: "account:parent", name: "Parent"})
      child = insert_account!(%{account_key: "account:child", name: "Child"})

      assert {:ok, updated_child} = Accounts.update_account(child, %{"parent_account_id" => parent.id})
      assert updated_child.parent_account_id == parent.id

      loaded_child = Accounts.get_account(child.id)
      loaded_parent = Accounts.get_account(parent.id)

      assert loaded_child.parent_account.id == parent.id
      assert Enum.map(loaded_parent.child_accounts, & &1.id) == [child.id]
    end

    test "update_account/2 rejects parent cycles" do
      parent = insert_account!(%{account_key: "account:cycle-parent", name: "Parent"})
      child = insert_account!(%{account_key: "account:cycle-child", name: "Child"})

      assert {:ok, _child} = Accounts.update_account(child, %{"parent_account_id" => parent.id})
      assert {:error, changeset} = Accounts.update_account(parent, %{"parent_account_id" => child.id})

      assert %{parent_account_id: ["can't be a child account"]} = errors_on(changeset)
    end

    test "list_parent_account_options/1 excludes the current account" do
      account = insert_account!(%{account_key: "account:option-current", name: "Current"})
      parent = insert_account!(%{account_key: "account:option-parent", name: "Parent"})

      options = Accounts.list_parent_account_options(account.id)

      assert Enum.map(options, & &1.id) == [parent.id]
    end
  end

  describe "delete_account/1" do
    test "removes the account and cascades to contacts, handles, invoices, terms, and events" do
      account = insert_account!(%{account_key: "account:to-delete", name: "To Delete"})

      contact =
        %Contact{}
        |> Contact.changeset(%{
          full_name: "Contact",
          email: "contact@example.com",
          account_id: account.id
        })
        |> Repo.insert!()

      handle =
        %AccountHandle{}
        |> AccountHandle.changeset(%{
          handle: "to-delete-handle",
          source: "enterprise",
          account_id: account.id
        })
        |> Repo.insert!()

      invoice =
        %Invoice{account_id: account.id}
        |> Invoice.changeset(%{
          external_id: "invoice:to-delete",
          source: "stripe",
          due_date: ~D[2026-06-01]
        })
        |> Repo.insert!()

      term =
        %Term{account_id: account.id}
        |> Term.changeset(%{
          source: "atlas",
          payment: "yearly",
          start_date: ~D[2026-01-01],
          total: Decimal.new("12000")
        })
        |> Repo.insert!()

      event = insert_event!(account, %{title: "Note", body: "body"})

      outcome =
        %Outcome{account_id: account.id}
        |> Outcome.changeset(%{
          title: "Reach adoption target",
          status: "active",
          health: "on_track",
          motion: "adoption"
        })
        |> Repo.insert!()

      assert {:ok, %Account{}} = Accounts.delete_account(account)

      refute Repo.get(Account, account.id)
      refute Repo.get(Contact, contact.id)
      refute Repo.get(AccountHandle, handle.id)
      refute Repo.get(Invoice, invoice.id)
      refute Repo.get(Term, term.id)
      refute Repo.get(Event, event.id)
      refute Repo.get(Outcome, outcome.id)
    end

    test "treats deleting an already removed account as success" do
      account = insert_account!(%{account_key: "account:stale-delete", name: "Stale Delete"})
      account_id = account.id

      assert {:ok, %Account{}} = Accounts.delete_account(account)
      assert {:ok, %Account{id: ^account_id}} = Accounts.delete_account(account)
    end

    test "returns a changeset error instead of crashing when the account owns a license" do
      account = insert_account!(%{account_key: "account:licensed", name: "Licensed Account"})
      key = "ONLINE-KEY-#{System.unique_integer([:positive])}"

      %License{account_id: account.id}
      |> License.issued_changeset(%{
        key: key,
        key_hash: Issuer.key_hash(key),
        signing_key: Base.encode64(:crypto.strong_rand_bytes(32)),
        expires_on: Date.utc_today() |> Date.add(365)
      })
      |> Repo.insert!()

      assert {:error, changeset} = Accounts.delete_account(account)
      assert "still has associated licenses" in errors_on(changeset).licenses
      assert Repo.get!(Account, account.id)
    end
  end

  describe "renew_term_changeset/2" do
    test "seeds a new term that continues the previous window and copies the commercials" do
      account = insert_account!(%{account_key: "account:renew", name: "Renew Co"})

      term =
        %Term{account_id: account.id}
        |> Term.changeset(%{
          source: "salesforce",
          external_id: "term:original",
          payment: "yearly",
          start_date: ~D[2025-07-15],
          end_date: ~D[2026-07-14],
          seats: 14,
          price_per_seat: Decimal.new("40"),
          discount: Decimal.new("100"),
          total: Decimal.new("6720"),
          currency: "EUR",
          on_premise: true,
          renewal_notice_weeks: 8,
          po_number: "PO-1"
        })
        |> Repo.insert!()

      changeset = Accounts.renew_term_changeset(account, term)

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :account_id) == account.id
      assert Ecto.Changeset.get_field(changeset, :source) == "atlas"
      refute Ecto.Changeset.get_field(changeset, :external_id)

      assert Ecto.Changeset.get_field(changeset, :start_date) == ~D[2026-07-15]
      assert Ecto.Changeset.get_field(changeset, :end_date) == ~D[2027-07-14]

      assert Ecto.Changeset.get_field(changeset, :payment) == "yearly"
      assert Ecto.Changeset.get_field(changeset, :seats) == 14
      assert Decimal.equal?(Ecto.Changeset.get_field(changeset, :price_per_seat), Decimal.new("40"))
      assert Decimal.equal?(Ecto.Changeset.get_field(changeset, :total), Decimal.new("6720"))
      assert Ecto.Changeset.get_field(changeset, :currency) == "EUR"
      assert Ecto.Changeset.get_field(changeset, :on_premise) == true
      assert Ecto.Changeset.get_field(changeset, :renewal_notice_weeks) == 8
      assert Ecto.Changeset.get_field(changeset, :po_number) == "PO-1"
    end

    test "leaves the end date open when the previous term had none" do
      account = insert_account!(%{account_key: "account:renew-open", name: "Renew Open"})

      term =
        %Term{account_id: account.id}
        |> Term.changeset(%{
          source: "atlas",
          payment: "whole-term",
          start_date: ~D[2024-01-01],
          total: Decimal.new("4800")
        })
        |> Repo.insert!()

      changeset = Accounts.renew_term_changeset(account, term)

      assert Ecto.Changeset.get_field(changeset, :start_date) == ~D[2024-01-01]
      assert Ecto.Changeset.get_field(changeset, :end_date) == nil
    end
  end

  describe "term commercial summary sync" do
    test "contract_value/2 prefers an active term over a future signed term" do
      today = Date.utc_today()

      account =
        insert_account!(%{
          account_key: "account:contract-value-active",
          name: "Contract Value Active",
          segment: :customer,
          currency: "EUR",
          current_value: Decimal.new("0")
        })

      %Term{account_id: account.id}
      |> Term.changeset(%{
        source: "atlas",
        payment: "yearly",
        start_date: Date.add(today, -30),
        end_date: Date.add(today, 30),
        total: Decimal.new("12000"),
        currency: "EUR"
      })
      |> Repo.insert!()

      %Term{account_id: account.id}
      |> Term.changeset(%{
        source: "atlas",
        payment: "yearly",
        start_date: Date.add(today, 31),
        end_date: Date.add(today, 395),
        total: Decimal.new("24000"),
        currency: "EUR"
      })
      |> Repo.insert!()

      loaded_account = Accounts.get_account(account.id)

      assert {value, "EUR"} = Accounts.contract_value(loaded_account)
      assert Decimal.equal?(value, Decimal.new("12000"))
    end

    test "create_term/2 updates the account renewal summary from the latest term" do
      account =
        insert_account!(%{
          account_key: "account:monday-renewal",
          name: "Monday",
          segment: :customer,
          currency: "EUR",
          current_value: Decimal.new("6720"),
          next_renewal_date: ~D[2026-08-01]
        })

      assert {:ok, _term} =
               Accounts.create_term(account, %{
                 "payment" => "yearly",
                 "start_date" => "2026-08-02",
                 "end_date" => "2027-08-01",
                 "total" => "12000",
                 "currency" => "EUR"
               })

      updated = Repo.get!(Account, account.id)

      assert Decimal.equal?(updated.current_value, Decimal.new("12000"))
      assert updated.currency == "EUR"
      assert updated.next_renewal_date == ~D[2027-08-01]

      assert [renewal] = Accounts.list_upcoming_renewals(today: ~D[2026-07-07])
      assert renewal.id == account.id
      assert renewal.next_renewal_date == ~D[2027-08-01]
    end

    test "updating an older term does not overwrite the latest commercial summary" do
      account =
        insert_account!(%{
          account_key: "account:term-order",
          name: "Term Order",
          segment: :customer
        })

      assert {:ok, older_term} =
               Accounts.create_term(account, %{
                 "payment" => "yearly",
                 "start_date" => "2025-01-01",
                 "end_date" => "2025-12-31",
                 "total" => "9000",
                 "currency" => "EUR"
               })

      assert {:ok, _latest_term} =
               Accounts.create_term(account, %{
                 "payment" => "yearly",
                 "start_date" => "2026-01-01",
                 "end_date" => "2026-12-31",
                 "total" => "12000",
                 "currency" => "EUR"
               })

      assert {:ok, _older_term} =
               Accounts.update_term(older_term, %{
                 "total" => "9900"
               })

      updated = Repo.get!(Account, account.id)

      assert Decimal.equal?(updated.current_value, Decimal.new("12000"))
      assert updated.next_renewal_date == ~D[2026-12-31]
    end
  end

  describe "mark_account_not_account/2" do
    test "hides the account from lists while preserving the row and identifiers" do
      account =
        insert_account!(%{
          account_key: "account:grafana",
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

      assert {:ok, marked} =
               Accounts.mark_account_not_account(account, %{
                 reason: "Vendor, not a customer account"
               })

      assert marked.not_an_account_at
      assert marked.not_an_account_reason == "Vendor, not a customer account"

      refute Enum.any?(Accounts.list_accounts(query: "Grafana"), &(&1.id == account.id))
      refute account.id in Accounts.list_account_ids()
      refute Enum.any?(Accounts.list_parent_account_options(), &(&1.id == account.id))

      stored = Accounts.get_account(account.id)
      assert stored.id == account.id
      assert stored.not_an_account_at
      assert [%AccountHandle{handle: "grafana.com"}] = stored.account_handles
    end
  end

  describe "list_account_ids/0" do
    test "returns persisted account ids" do
      first = insert_account!(%{account_key: "account:first", name: "First"})
      second = insert_account!(%{account_key: "account:second", name: "Second"})

      assert Accounts.list_account_ids() |> Enum.sort() == Enum.sort([first.id, second.id])
    end

    test "returns an empty list when there are no accounts" do
      assert Accounts.list_account_ids() == []
    end
  end

  describe "refresh_overview_summary/1" do
    test "updates the account with the generated markdown summary" do
      account =
        insert_account!(%{
          account_key: "account:summary",
          name: "Summary Account",
          segment: :customer
        })

      event =
        insert_event!(account, %{
          title: "Renewal call",
          body: "Customer asked for the procurement timeline.",
          occurred_at: ~U[2026-05-06 12:00:00Z]
        })

      older_event =
        insert_event!(account, %{
          title: "Discovery call",
          body: "Customer confirmed the evaluation scope.",
          occurred_at: ~U[2026-05-01 12:00:00Z]
        })

      summary = "**Summary Account** is preparing renewal next steps.\n\n- Confirm procurement timeline."
      user = insert_user!("overview-summary-owner-#{System.unique_integer([:positive])}@example.com")

      summarize = fn loaded_account ->
        assert loaded_account.id == account.id
        assert Enum.map(loaded_account.events, & &1.id) == [event.id, older_event.id]

        {:ok, summary}
      end

      assert {:ok, updated_account} =
               Atlas.Audit.with_context(%{actor: user, interface: "dashboard"}, fn ->
                 Accounts.refresh_overview_summary(account.id, summarize: summarize)
               end)

      assert updated_account.overview_summary == summary
      assert updated_account.overview_summary_generated_at
      assert updated_account.overview_summary_generated_at.microsecond == {0, 0}

      reloaded_account = Repo.get!(Account, account.id)
      assert reloaded_account.overview_summary == summary
      assert reloaded_account.overview_summary_generated_at == updated_account.overview_summary_generated_at

      activity = Repo.get_by!(Activity, action: "account.overview_summary_refreshed", target_id: account.id)
      assert activity.metadata["summary_length"] == String.length(summary)
      assert activity.interface == "dashboard"
      assert activity.actor_id == user.id
    end

    test "returns :not_found when the account does not exist" do
      assert {:error, :not_found} = Accounts.refresh_overview_summary(Atlas.UUIDv7.generate())
    end

    test "returns agent errors without updating the account" do
      account = insert_account!(%{account_key: "account:no-summary", name: "No Summary"})

      summarize = fn _account -> {:error, :llm_not_configured} end

      assert {:error, :llm_not_configured} =
               Accounts.refresh_overview_summary(account.id, summarize: summarize)

      reloaded_account = Repo.get!(Account, account.id)
      assert reloaded_account.overview_summary == nil
      assert reloaded_account.overview_summary_generated_at == nil
    end
  end

  describe "customer outcomes" do
    test "creates a measurable account outcome" do
      account = insert_account!(%{account_key: "account:outcome", name: "Outcome Account"})
      owner = insert_user!("outcome-owner@example.com")

      assert {:ok, outcome} =
               Accounts.create_outcome(
                 account,
                 %{
                   "title" => "Reach weekly adoption target",
                   "motion" => "adoption",
                   "health" => "on_track",
                   "success_measure" => "Weekly active developers",
                   "baseline" => "12",
                   "target" => "30",
                   "target_date" => "2026-08-31"
                 },
                 owner
               )

      assert outcome.account_id == account.id
      assert outcome.owner_id == owner.id
      assert outcome.status == "active"
      assert outcome.target_date == ~D[2026-08-31]
      assert Enum.map(Accounts.list_outcomes(account), & &1.id) == [outcome.id]
    end

    test "records evidence-backed reviews and projects health onto the outcome" do
      account = insert_account!(%{account_key: "account:review", name: "Review Account"})
      reviewer = insert_user!("outcome-reviewer@example.com")
      outcome = insert_outcome!(account, %{health: "unknown", reviewed_at: nil})

      assert {:ok, review} =
               Accounts.create_outcome_review(
                 outcome,
                 %{
                   "health" => "at_risk",
                   "summary" => "Usage is growing, but the second rollout slipped.",
                   "evidence" => %{
                     "items" => [
                       %{"source" => "product_usage", "detail" => "Weekly usage rose from twelve to eighteen."}
                     ]
                   },
                   "recommendation" => "Pair with the delayed team on its first successful rollout.",
                   "reviewed_at" => "2026-07-10T09:00:00Z"
                 },
                 reviewer
               )

      assert review.author_id == reviewer.id
      assert review.health == "at_risk"

      projected = Accounts.get_outcome(outcome.id)
      assert projected.health == "at_risk"
      assert projected.reviewed_at == ~U[2026-07-10 09:00:00Z]
      assert Enum.map(projected.reviews, & &1.id) == [review.id]
    end

    test "marks an achieved outcome with closure timestamps" do
      account = insert_account!(%{account_key: "account:achieved", name: "Achieved Account"})
      outcome = insert_outcome!(account)

      assert {:ok, achieved} = Accounts.update_outcome(outcome, %{"status" => "achieved"})
      assert achieved.status == "achieved"
      assert %DateTime{} = achieved.achieved_at
      assert %DateTime{} = achieved.closed_at
    end
  end

  test "mark_outcome_review_company_slack_posted stamps the review post timestamp" do
    account =
      insert_account!(%{
        account_key: "account:review-posted",
        name: "Review Posted",
        segment: :customer
      })

    posted_at = ~U[2026-07-12 09:30:45Z]

    assert {:ok, updated} = Accounts.mark_outcome_review_company_slack_posted(account, posted_at)
    assert updated.outcome_review_company_slack_posted_at == posted_at
    assert Accounts.get_account(account.id).outcome_review_company_slack_posted_at == posted_at
  end

  test "list_overview_summary_candidate_ids follows profile and activity changes" do
    generated_at = ~U[2026-05-01 09:00:00Z]
    later_activity_at = ~U[2026-05-03 09:00:00Z]

    missing_summary = insert_account!(%{account_key: "account:missing-summary", name: "Missing Summary"})

    stale_activity =
      insert_account!(%{account_key: "account:activity-summary", name: "Activity Summary"})
      |> stamp_summary_inputs!(%{
        overview_summary: "Old activity summary",
        overview_summary_generated_at: generated_at,
        latest_activity_at: later_activity_at,
        updated_at: generated_at
      })

    stale_profile =
      insert_account!(%{account_key: "account:profile-summary", name: "Profile Summary"})
      |> stamp_summary_inputs!(%{
        overview_summary: "Old profile summary",
        overview_summary_generated_at: generated_at,
        updated_at: later_activity_at
      })

    current =
      insert_account!(%{account_key: "account:current-summary", name: "Current Summary"})
      |> stamp_summary_inputs!(%{
        overview_summary: "Current summary",
        overview_summary_generated_at: generated_at,
        updated_at: generated_at
      })

    candidate_ids = Accounts.list_overview_summary_candidate_ids()

    assert missing_summary.id in candidate_ids
    assert stale_activity.id in candidate_ids
    assert stale_profile.id in candidate_ids
    refute current.id in candidate_ids
  end

  describe "outcome overview queries" do
    test "list_attention_outcomes orders off-track outcomes before at-risk outcomes" do
      off_track_account =
        insert_account!(%{account_key: "account:off-track", name: "Off Track"})

      at_risk_account =
        insert_account!(%{account_key: "account:at-risk", name: "At Risk"})

      achieved_account =
        insert_account!(%{account_key: "account:achieved-skip", name: "Achieved Skip"})

      off_track =
        insert_outcome!(off_track_account, %{
          title: "Complete security review",
          health: "off_track",
          target_date: ~D[2026-07-20]
        })

      at_risk =
        insert_outcome!(at_risk_account, %{
          title: "Reach adoption target",
          health: "at_risk",
          target_date: ~D[2026-07-18]
        })

      _achieved =
        insert_outcome!(achieved_account, %{
          title: "Finished outcome",
          status: "achieved",
          health: "on_track"
        })

      {outcomes, meta} = Accounts.list_attention_outcomes()

      assert Enum.map(outcomes, & &1.id) == [off_track.id, at_risk.id]
      assert Enum.all?(outcomes, & &1.account)
      refute meta.has_next_page?
    end

    test "list_attention_outcomes paginates through Flop" do
      account = insert_account!(%{account_key: "account:attention-pages", name: "Attention Pages"})

      _first =
        insert_outcome!(account, %{
          title: "First outcome",
          health: "off_track",
          target_date: ~D[2026-07-18]
        })

      _second =
        insert_outcome!(account, %{
          title: "Second outcome",
          health: "at_risk",
          target_date: ~D[2026-07-19]
        })

      {page_one, meta_one} = Accounts.list_attention_outcomes(limit: 1, offset: 0)
      {page_two, meta_two} = Accounts.list_attention_outcomes(limit: 1, offset: 1)

      assert length(page_one) == 1
      assert length(page_two) == 1
      assert meta_one.has_next_page?
      assert meta_two.has_previous_page?
    end

    test "list_outcome_review_accounts returns active customers with active outcomes" do
      customer =
        insert_account!(%{
          account_key: "account:review-customer",
          name: "Review Customer",
          segment: :customer,
          latest_activity_at: ~U[2026-07-10 10:00:00Z]
        })

      lead =
        insert_account!(%{
          account_key: "account:review-lead",
          name: "Review Lead",
          segment: :lead,
          latest_activity_at: ~U[2026-07-11 10:00:00Z]
        })

      customer_outcome = insert_outcome!(customer, %{title: "Customer adoption"})
      _lead_outcome = insert_outcome!(lead, %{title: "Lead evaluation"})

      assert [loaded_customer] = Accounts.list_outcome_review_accounts()
      assert loaded_customer.id == customer.id
      assert Enum.map(loaded_customer.outcomes, & &1.id) == [customer_outcome.id]
    end

    test "list_outcome_review_updates returns recent active-customer evidence" do
      customer =
        insert_account!(%{
          account_key: "account:review-updates",
          name: "Review Updates",
          segment: :customer
        })

      lead =
        insert_account!(%{
          account_key: "account:review-updates-lead",
          name: "Review Updates Lead",
          segment: :lead
        })

      customer_update =
        insert_event!(customer, %{title: "Adoption review", occurred_at: ~U[2026-07-10 10:00:00Z]})

      _lead_update =
        insert_event!(lead, %{title: "Lead update", occurred_at: ~U[2026-07-11 10:00:00Z]})

      assert Accounts.list_outcome_review_updates() |> Enum.map(& &1.id) == [customer_update.id]
    end

    test "sales_overview_counts reflects outcome health and overdue targets" do
      on_track_account =
        insert_account!(%{account_key: "account:counts-on-track", name: "Counts On Track"})

      off_track_account =
        insert_account!(%{account_key: "account:counts-off-track", name: "Counts Off Track"})

      _without_outcome =
        insert_account!(%{account_key: "account:counts-none", name: "Counts None"})

      _on_track =
        insert_outcome!(on_track_account, %{
          health: "on_track",
          target_date: ~D[2026-08-01]
        })

      _off_track =
        insert_outcome!(off_track_account, %{
          health: "off_track",
          target_date: ~D[2026-07-01]
        })

      counts = Accounts.sales_overview_counts(~D[2026-07-15])

      assert counts.on_track == 1
      assert counts.off_track == 1
      assert counts.at_risk == 0
      assert counts.overdue_outcomes == 1
      assert counts.accounts_without_outcomes == 1
    end

    test "revenue_snapshot counts active customer value" do
      insert_account!(%{
        account_key: "account:closed-won-customer",
        name: "Closed Won Customer",
        segment: :customer,
        deal_stage: "closed_won",
        currency: "EUR",
        current_value: Decimal.new("12000.00"),
        next_renewal_date: ~D[2027-01-01]
      })

      snapshot = Accounts.revenue_snapshot()

      assert Decimal.equal?(snapshot.monthly_revenue_eur, Decimal.new("1000.00"))
      assert Decimal.equal?(snapshot.estimated_arr_eur, Decimal.new("12000.00"))
      assert snapshot.renewal_base_count == 1
    end
  end

  defp insert_account!(attrs) do
    defaults = %{
      account_key: "account:#{System.unique_integer([:positive])}",
      name: "Account",
      segment: :lead
    }

    %Account{}
    |> Account.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_outcome!(account, attrs \\ %{}) do
    defaults = %{
      title: "Reach the customer outcome",
      status: "active",
      health: "on_track",
      motion: "adoption",
      success_measure: "Weekly active developers",
      baseline: "10",
      target: "30",
      target_date: ~D[2026-08-31]
    }

    %Outcome{account_id: account.id}
    |> Outcome.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp stamp_summary_inputs!(%Account{} = account, attrs) do
    query = Ecto.Query.from(account in Account, where: account.id == ^account.id)

    {1, nil} = Repo.update_all(query, set: Map.to_list(attrs))
    Repo.get!(Account, account.id)
  end

  defp insert_user!(email) do
    %User{}
    |> User.changeset(%{email: email, name: "Atlas User"})
    |> Repo.insert!()
  end

  defp insert_event!(account, attrs) do
    defaults = %{
      external_id: "event:#{System.unique_integer([:positive])}",
      source: "atlas",
      kind: "note",
      title: "Note",
      body: "Body",
      occurred_at: ~U[2026-05-01 10:00:00Z],
      account_id: account.id
    }

    %Event{}
    |> Event.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp account_ids(accounts), do: Enum.map(accounts, & &1.id)
end
