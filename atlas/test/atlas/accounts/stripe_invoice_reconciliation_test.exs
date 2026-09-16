defmodule Atlas.Accounts.StripeInvoiceReconciliationTest do
  use Atlas.DataCase, async: true
  use Mimic
  use Oban.Testing, repo: Atlas.Repo

  alias Atlas.Accounts
  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Invoice
  alias Atlas.Accounts.InvoicePaidNotifier
  alias Atlas.Accounts.Workers.ScheduleStripeInvoiceReconciliations
  alias Atlas.Accounts.Workers.StripeInvoiceReconciliationWorker
  alias Atlas.Audit.Activity
  alias Atlas.Stripe.Invoice, as: StripeInvoice
  alias Atlas.TestSupport.StripeClient

  setup :verify_on_exit!

  setup do
    stub(InvoicePaidNotifier, :notify, fn _account, _invoice -> :ok end)
    :ok
  end

  test "reconcile_stripe_invoices/1 upserts Stripe invoices" do
    account = insert_account!(%{stripe_customer_id: "cus_123"})

    put_stripe_invoices(
      "cus_123",
      {:ok,
       [
         %StripeInvoice{
           id: "in_123",
           number: "TUIST-8002",
           due_date: ~D[2026-03-01],
           amount_value: Decimal.new("30000.00"),
           amount_currency: "USD",
           status: "open",
           hosted_url: "https://stripe.example/invoices/in_123"
         }
       ]}
    )

    assert {:ok, %{account_id: account_id, invoices: 1}} = Accounts.reconcile_stripe_invoices(account)
    assert account_id == account.id

    invoice = Repo.get_by!(Invoice, source: "stripe", external_id: "in_123")
    assert invoice.account_id == account.id
    assert invoice.number == "TUIST-8002"
    assert invoice.due_date == ~D[2026-03-01]
    assert Decimal.equal?(invoice.amount_value, Decimal.new("30000.00"))
    assert invoice.amount_currency == "USD"
    assert invoice.status == "open"
    assert invoice.stripe_url == "https://stripe.example/invoices/in_123"

    activity = Repo.get_by!(Activity, action: "account_invoice.stripe_reconciled", target_id: account.id)
    assert activity.metadata["invoice_count"] == 1
  end

  test "reconcile_stripe_invoices/1 updates existing Stripe invoices and notifies on paid transitions" do
    account = insert_account!(%{stripe_customer_id: "cus_123"})

    insert_invoice!(account, %{
      external_id: "in_123",
      source: "stripe",
      number: "TUIST-8002",
      due_date: ~D[2026-03-01],
      amount_value: Decimal.new("30000.00"),
      amount_currency: "USD",
      status: "open",
      stripe_url: "https://stripe.example/invoices/in_123"
    })

    put_stripe_invoices(
      "cus_123",
      {:ok,
       [
         %StripeInvoice{
           id: "in_123",
           number: "TUIST-8002",
           due_date: ~D[2026-03-01],
           amount_value: Decimal.new("30000.00"),
           amount_currency: "USD",
           status: "paid",
           hosted_url: "https://stripe.example/invoices/in_123"
         }
       ]}
    )

    test_pid = self()

    expect(InvoicePaidNotifier, :notify, fn notified_account, notified_invoice ->
      send(test_pid, {:notified, notified_account.id, notified_invoice.external_id, notified_invoice.status})
      :ok
    end)

    assert {:ok, %{account_id: account_id, invoices: 1}} = Accounts.reconcile_stripe_invoices(account)
    assert account_id == account.id

    invoice = Repo.get_by!(Invoice, source: "stripe", external_id: "in_123")
    assert invoice.status == "paid"

    assert_received {:notified, ^account_id, "in_123", "paid"}
  end

  test "reconcile_stripe_invoices/1 does not notify when a brand-new invoice arrives already paid" do
    account = insert_account!(%{stripe_customer_id: "cus_historical"})

    put_stripe_invoices(
      "cus_historical",
      {:ok,
       [
         %StripeInvoice{
           id: "in_historical",
           number: "TUIST-7000",
           due_date: ~D[2024-01-01],
           amount_value: Decimal.new("100.00"),
           amount_currency: "USD",
           status: "paid",
           hosted_url: "https://stripe.example/invoices/in_historical"
         }
       ]}
    )

    reject(&InvoicePaidNotifier.notify/2)

    assert {:ok, %{invoices: 1}} = Accounts.reconcile_stripe_invoices(account)
    assert Repo.get_by!(Invoice, source: "stripe", external_id: "in_historical").status == "paid"
  end

  test "reconcile_stripe_invoices/1 does not notify when an already-paid invoice is re-synced" do
    account = insert_account!(%{stripe_customer_id: "cus_resync"})

    insert_invoice!(account, %{
      external_id: "in_resync",
      source: "stripe",
      number: "TUIST-7100",
      due_date: ~D[2026-03-01],
      amount_value: Decimal.new("500.00"),
      amount_currency: "USD",
      status: "paid",
      stripe_url: "https://stripe.example/invoices/in_resync"
    })

    put_stripe_invoices(
      "cus_resync",
      {:ok,
       [
         %StripeInvoice{
           id: "in_resync",
           number: "TUIST-7100",
           due_date: ~D[2026-03-01],
           amount_value: Decimal.new("500.00"),
           amount_currency: "USD",
           status: "paid",
           hosted_url: "https://stripe.example/invoices/in_resync"
         }
       ]}
    )

    reject(&InvoicePaidNotifier.notify/2)

    assert {:ok, %{invoices: 1}} = Accounts.reconcile_stripe_invoices(account)
  end

  test "reconcile_stripe_invoices/1 returns not found for missing accounts" do
    assert {:error, :not_found} = Accounts.reconcile_stripe_invoices(Atlas.UUIDv7.generate())
  end

  test "reconcile_stripe_invoices/1 upserts draft invoices with no due date" do
    account = insert_account!(%{stripe_customer_id: "cus_drafts"})

    put_stripe_invoices(
      "cus_drafts",
      {:ok,
       [
         %StripeInvoice{
           id: "in_draft",
           number: nil,
           due_date: nil,
           amount_value: Decimal.new("100.00"),
           amount_currency: "USD",
           status: "draft"
         }
       ]}
    )

    assert {:ok, %{invoices: 1}} = Accounts.reconcile_stripe_invoices(account)

    invoice = Repo.get_by!(Invoice, source: "stripe", external_id: "in_draft")
    assert invoice.due_date == nil
    assert invoice.status == "draft"
  end

  test "reconcile_stripe_invoices/1 logs and skips invalid invoices, persisting the rest" do
    account = insert_account!(%{stripe_customer_id: "cus_partial"})

    put_stripe_invoices(
      "cus_partial",
      {:ok,
       [
         # missing :id — should fail validate_required and be skipped
         %StripeInvoice{
           id: nil,
           due_date: ~D[2026-04-01],
           amount_value: Decimal.new("10.00"),
           amount_currency: "USD",
           status: "open"
         },
         %StripeInvoice{
           id: "in_ok",
           number: "TUIST-9000",
           due_date: ~D[2026-04-15],
           amount_value: Decimal.new("20.00"),
           amount_currency: "USD",
           status: "open"
         }
       ]}
    )

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert {:ok, %{invoices: 1}} = Accounts.reconcile_stripe_invoices(account)
      end)

    assert log =~ "Skipping Stripe invoice"
    assert Repo.get_by!(Invoice, source: "stripe", external_id: "in_ok").account_id == account.id
  end

  test "upcoming_invoices/2 includes invoices without a due date" do
    account = insert_account!(%{stripe_customer_id: "cus_upcoming"})

    put_stripe_invoices(
      "cus_upcoming",
      {:ok,
       [
         %StripeInvoice{
           id: "in_no_date",
           due_date: nil,
           amount_value: Decimal.new("1.00"),
           amount_currency: "USD",
           status: "draft"
         },
         %StripeInvoice{
           id: "in_future",
           due_date: ~D[2099-01-01],
           amount_value: Decimal.new("2.00"),
           amount_currency: "USD",
           status: "open"
         },
         %StripeInvoice{
           id: "in_past",
           due_date: ~D[2000-01-01],
           amount_value: Decimal.new("3.00"),
           amount_currency: "USD",
           status: "paid"
         }
       ]}
    )

    assert {:ok, _} = Accounts.reconcile_stripe_invoices(account)
    account = Accounts.get_account(account.id)

    upcoming_ids =
      account
      |> Accounts.upcoming_invoices()
      |> Enum.map(& &1.external_id)

    assert "in_future" in upcoming_ids
    assert "in_no_date" in upcoming_ids
    refute "in_past" in upcoming_ids
  end

  test "reconciled_stripe_invoices/1 sorts drafts (no due date) above dated invoices" do
    account = insert_account!(%{stripe_customer_id: "cus_sort"})

    put_stripe_invoices(
      "cus_sort",
      {:ok,
       [
         %StripeInvoice{
           id: "in_dated",
           due_date: ~D[2026-04-01],
           amount_value: Decimal.new("1.00"),
           amount_currency: "USD",
           status: "open"
         },
         %StripeInvoice{
           id: "in_draft",
           due_date: nil,
           amount_value: Decimal.new("2.00"),
           amount_currency: "USD",
           status: "draft"
         }
       ]}
    )

    assert {:ok, _} = Accounts.reconcile_stripe_invoices(account)
    account = Accounts.get_account(account.id)

    [first, second] = Accounts.reconciled_stripe_invoices(account)
    assert first.external_id == "in_draft"
    assert second.external_id == "in_dated"
  end

  test "list_stripe_customer_account_ids/0 returns only accounts with Stripe customers" do
    first = insert_account!(%{name: "A", stripe_customer_id: "cus_a"})
    second = insert_account!(%{name: "B", stripe_customer_id: "cus_b"})
    insert_account!(%{name: "C"})

    assert Accounts.list_stripe_customer_account_ids() == [first.id, second.id]
  end

  test "scheduler returns zero when there are no Stripe customers to schedule" do
    assert {:ok, 0} = perform_job(ScheduleStripeInvoiceReconciliations, %{})
  end

  test "scheduler enqueues one reconciliation job per Stripe account" do
    first = insert_account!(%{name: "A", stripe_customer_id: "cus_a"})
    second = insert_account!(%{name: "B", stripe_customer_id: "cus_b"})
    insert_account!(%{name: "C"})

    assert {:ok, 2} = perform_job(ScheduleStripeInvoiceReconciliations, %{})

    assert_enqueued(worker: StripeInvoiceReconciliationWorker, args: %{"account_id" => first.id})
    assert_enqueued(worker: StripeInvoiceReconciliationWorker, args: %{"account_id" => second.id})
  end

  test "scheduler stops when job insertion fails" do
    error_changeset =
      %Oban.Job{}
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.add_error(:args, "is invalid")

    insert = fn
      %Ecto.Changeset{changes: %{args: %{account_id: "first"}}} = changeset ->
        {:ok, changeset}

      %Ecto.Changeset{changes: %{args: %{account_id: "second"}}} ->
        {:error, error_changeset}
    end

    assert {:error, ^error_changeset} =
             ScheduleStripeInvoiceReconciliations.perform(%Oban.Job{},
               list_account_ids: fn -> ["first", "second"] end,
               insert: insert
             )
  end

  test "worker reconciles one Stripe account" do
    account = insert_account!(%{stripe_customer_id: "cus_worker"})
    insert_account!(%{stripe_customer_id: "cus_other"})

    put_stripe_invoices(
      "cus_worker",
      {:ok,
       [
         %StripeInvoice{
           id: "in_worker",
           number: "TUIST-8004",
           due_date: ~D[2026-05-01],
           amount_value: Decimal.new("900.00"),
           amount_currency: "USD",
           status: "paid"
         }
       ]}
    )

    assert :ok = perform_job(StripeInvoiceReconciliationWorker, %{account_id: account.id})

    assert Repo.get_by!(Invoice, source: "stripe", external_id: "in_worker").account_id == account.id
  end

  test "worker cancels when the account is missing" do
    assert {:cancel, :account_not_found} =
             perform_job(StripeInvoiceReconciliationWorker, %{account_id: Atlas.UUIDv7.generate()})
  end

  test "worker cancels when reconciliation is disabled for the account" do
    account = insert_account!(%{})

    assert {:cancel, :stripe_invoice_reconciliation_disabled} =
             perform_job(StripeInvoiceReconciliationWorker, %{account_id: account.id})
  end

  test "worker fails when the account reconciliation fails" do
    account = insert_account!(%{stripe_customer_id: "cus_failed"})

    put_stripe_invoices("cus_failed", {:error, :timeout})

    assert {:error, :timeout} =
             perform_job(StripeInvoiceReconciliationWorker, %{account_id: account.id})
  end

  defp put_stripe_invoices(customer_id, result) do
    StripeClient.put_list_invoices(customer_id, fn
      [limit: 100] -> result
    end)
  end

  defp insert_account!(attrs) do
    defaults = %{
      account_key: "account:#{System.unique_integer([:positive])}",
      name: "Account",
      segment: :customer
    }

    %Account{}
    |> Account.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_invoice!(account, attrs) do
    defaults = %{
      external_id: "invoice:#{System.unique_integer([:positive])}",
      source: "stripe",
      due_date: ~D[2026-01-01],
      amount_value: Decimal.new("100.00"),
      amount_currency: "USD",
      status: "open"
    }

    %Invoice{account_id: account.id}
    |> Invoice.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end
end
