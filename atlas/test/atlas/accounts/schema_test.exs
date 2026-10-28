defmodule Atlas.Accounts.SchemaTest do
  use ExUnit.Case, async: true

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.AccountHandle
  alias Atlas.Accounts.Contact
  alias Atlas.Accounts.DealStage
  alias Atlas.Accounts.Event
  alias Atlas.Accounts.Invoice
  alias Atlas.Accounts.Outcome

  test "account changeset no longer requires sync bookkeeping" do
    changeset =
      Account.changeset(%Account{}, %{
        account_key: "console:northstar",
        name: "Northstar",
        segment: :customer,
        last_synced_at: ~U[2026-05-01 10:00:00Z]
      })

    assert changeset.valid?
    refute Map.has_key?(changeset.changes, :last_synced_at)
  end

  test "account edit changeset normalizes editable fields" do
    changeset =
      Account.edit_changeset(%Account{name: "Northstar", segment: :lead}, %{
        name: " Northstar Retail ",
        segment: :customer,
        deal_stage: " legal_review ",
        currency: " usd ",
        current_value: "42.50",
        description: " ",
        primary_domain: " northstar.example.com ",
        stripe_customer_id: ""
      })

    assert changeset.valid?
    assert Ecto.Changeset.get_change(changeset, :name) == "Northstar Retail"
    assert Ecto.Changeset.get_change(changeset, :deal_stage) == "legal_review"
    assert Ecto.Changeset.get_change(changeset, :currency) == "USD"
    assert Ecto.Changeset.get_change(changeset, :description) == nil
    assert Ecto.Changeset.get_change(changeset, :primary_domain) == "northstar.example.com"
    assert Ecto.Changeset.get_change(changeset, :stripe_customer_id) == nil
  end

  test "account changeset validates deal stages" do
    valid_changeset =
      Account.changeset(%Account{}, %{
        account_key: "console:stage",
        name: "Northstar",
        segment: :lead,
        deal_stage: List.first(DealStage.keys())
      })

    invalid_changeset =
      Account.changeset(%Account{}, %{
        account_key: "console:invalid-stage",
        name: "Northstar",
        segment: :lead,
        deal_stage: "not-a-stage"
      })

    assert valid_changeset.valid?
    refute invalid_changeset.valid?
    assert %{deal_stage: ["is invalid"]} = errors_on(invalid_changeset)
  end

  test "account changeset validates hosting" do
    valid_changeset =
      Account.changeset(%Account{}, %{
        account_key: "console:hosting",
        name: "Northstar",
        segment: :customer,
        hosting: "self_hosted"
      })

    invalid_changeset =
      Account.changeset(%Account{}, %{
        account_key: "console:invalid-hosting",
        name: "Northstar",
        segment: :customer,
        hosting: "dedicated"
      })

    assert valid_changeset.valid?
    refute invalid_changeset.valid?
    assert %{hosting: ["is invalid"]} = errors_on(invalid_changeset)
  end

  test "account changeset stamps deal stage changes instead of accepting timestamps from params" do
    supplied_timestamp = ~U[2026-01-01 00:00:00Z]

    changeset =
      Account.changeset(%Account{}, %{
        account_key: "console:stage-stamp",
        name: "Northstar",
        segment: :lead,
        deal_stage: "legal_review",
        deal_stage_changed_at: supplied_timestamp
      })

    assert changeset.valid?
    assert %DateTime{} = stamped_at = Ecto.Changeset.get_change(changeset, :deal_stage_changed_at)
    assert stamped_at != supplied_timestamp
  end

  test "account edit changeset clears the deal stage none sentinel" do
    changeset =
      Account.edit_changeset(
        %Account{name: "Northstar", segment: :lead, deal_stage: "discovery"},
        %{name: "Northstar", segment: :lead, deal_stage: "_none"}
      )

    assert changeset.valid?
    assert Map.has_key?(changeset.changes, :deal_stage)
    assert Ecto.Changeset.fetch_change(changeset, :deal_stage) == {:ok, nil}
  end

  test "account edit changeset rejects using the same account as parent" do
    account_id = Ecto.UUID.generate()

    changeset =
      Account.edit_changeset(
        %Account{id: account_id, name: "Northstar", segment: :lead},
        %{parent_account_id: account_id}
      )

    refute changeset.valid?
    assert %{parent_account_id: ["can't be the same account"]} = errors_on(changeset)
  end

  test "account edit changeset clears the parent account none sentinel" do
    parent_account_id = Ecto.UUID.generate()

    changeset =
      Account.edit_changeset(
        %Account{name: "Northstar", segment: :lead, parent_account_id: parent_account_id},
        %{parent_account_id: "_none"}
      )

    assert changeset.valid?
    assert Map.has_key?(changeset.changes, :parent_account_id)
    assert Ecto.Changeset.fetch_change(changeset, :parent_account_id) == {:ok, nil}
  end

  test "outcome changeset normalizes its measurable fields" do
    changeset =
      Outcome.changeset(%Outcome{account_id: Ecto.UUID.generate()}, %{
        title: " Reduce build feedback time ",
        motion: "evaluation",
        status: "active",
        health: "at_risk",
        success_measure: " Median feedback time ",
        baseline: "22 minutes",
        target: "12 minutes"
      })

    assert changeset.valid?
    assert Ecto.Changeset.get_change(changeset, :title) == "Reduce build feedback time"
    assert Ecto.Changeset.get_change(changeset, :success_measure) == "Median feedback time"
  end

  test "contact changeset ignores importer-only fields" do
    changeset =
      Contact.changeset(%Contact{}, %{
        account_id: Ecto.UUID.generate(),
        full_name: "Maya Chen",
        email: "MAYA@EXAMPLE.COM",
        operate_person_id: "person_123",
        metadata: %{"company_ids" => ["company_123"]}
      })

    assert changeset.valid?
    assert Ecto.Changeset.get_change(changeset, :email) == "maya@example.com"
    refute Map.has_key?(changeset.changes, :operate_person_id)
    refute Map.has_key?(changeset.changes, :metadata)
  end

  test "contact edit changeset trims optional fields" do
    changeset =
      Contact.edit_changeset(%Contact{full_name: "Maya Chen", email: "maya@example.com"}, %{
        full_name: " Maya Chen ",
        email: " MAYA@EXAMPLE.COM ",
        title: " ",
        notes: " Prefers async follow-ups "
      })

    assert changeset.valid?
    assert Ecto.Changeset.get_field(changeset, :full_name) == "Maya Chen"
    assert Ecto.Changeset.get_field(changeset, :email) == "maya@example.com"
    assert Ecto.Changeset.get_change(changeset, :title) == nil
    assert Ecto.Changeset.get_change(changeset, :notes) == "Prefers async follow-ups"
  end

  test "account handle changeset ignores metadata" do
    changeset =
      AccountHandle.changeset(%AccountHandle{}, %{
        account_id: Ecto.UUID.generate(),
        handle: " northstar-main ",
        source: "console",
        metadata: %{"environment" => "production"}
      })

    assert changeset.valid?
    assert Ecto.Changeset.get_change(changeset, :handle) == "northstar-main"
    refute Map.has_key?(changeset.changes, :metadata)
  end

  test "invoice changeset ignores metadata" do
    account_id = Ecto.UUID.generate()
    injected_account_id = Ecto.UUID.generate()

    changeset =
      Invoice.changeset(%Invoice{account_id: account_id}, %{
        account_id: injected_account_id,
        external_id: "invoice:northstar:1",
        source: "console",
        number: " TUIST-8002 ",
        due_date: ~D[2026-07-01],
        amount_currency: " usd ",
        metadata: %{"raw" => true}
      })

    assert changeset.valid?
    assert Ecto.Changeset.get_field(changeset, :account_id) == account_id
    refute Map.has_key?(changeset.changes, :account_id)
    assert Ecto.Changeset.get_change(changeset, :number) == "TUIST-8002"
    assert Ecto.Changeset.get_change(changeset, :amount_currency) == "USD"
    refute Map.has_key?(changeset.changes, :metadata)
  end

  test "outcome changeset keeps foreign keys programmatic" do
    account_id = Ecto.UUID.generate()
    owner_id = Ecto.UUID.generate()
    source_event_id = Ecto.UUID.generate()

    changeset =
      Outcome.changeset(
        %Outcome{
          account_id: account_id,
          owner_id: owner_id,
          source_event_id: source_event_id
        },
        %{
          account_id: Ecto.UUID.generate(),
          owner_id: Ecto.UUID.generate(),
          source_event_id: Ecto.UUID.generate(),
          status: "active",
          health: "on_track",
          motion: "adoption",
          title: "Reach weekly adoption target"
        }
      )

    assert changeset.valid?
    assert Ecto.Changeset.get_field(changeset, :account_id) == account_id
    assert Ecto.Changeset.get_field(changeset, :owner_id) == owner_id
    assert Ecto.Changeset.get_field(changeset, :source_event_id) == source_event_id
    refute Map.has_key?(changeset.changes, :account_id)
    refute Map.has_key?(changeset.changes, :owner_id)
    refute Map.has_key?(changeset.changes, :source_event_id)
  end

  test "event changeset requires timeline identity fields" do
    changeset =
      Event.changeset(%Event{}, %{
        account_id: Ecto.UUID.generate(),
        source: "atlas",
        kind: "note",
        body: "Missing title and occurrence"
      })

    refute changeset.valid?

    assert %{external_id: ["can't be blank"], title: ["can't be blank"], occurred_at: ["can't be blank"]} =
             errors_on(changeset)
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
  end
end
