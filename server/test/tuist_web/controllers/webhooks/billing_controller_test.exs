defmodule TuistWeb.Webhooks.BillingControllerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Billing.Workers.CreateRunnerPrepaidGrantWorker
  alias Tuist.Billing.Workers.PaymentFailedNotificationWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.Webhooks.BillingController

  describe "handle_event/1 for customer.updated" do
    test "acknowledges repeated updates for a customer Tuist didn't create without changing another account" do
      user = AccountsFixtures.user_fixture(preload: [:account])
      account = user.account
      reject(Sentry, :capture_message, 2)

      event = %Stripe.Event{
        type: "customer.updated",
        data: %{
          object: %Stripe.Customer{
            id: "cus_unknown_#{System.unique_integer([:positive])}",
            email: "unknown-customer@example.com",
            metadata: %{}
          }
        }
      }

      assert :ok = BillingController.handle_event(event)
      assert :ok = BillingController.handle_event(event)

      assert {:ok, updated_account} = Accounts.get_account_by_id(account.id)
      assert updated_account.billing_email == account.billing_email
    end

    test "updates billing email when customer is found" do
      user = AccountsFixtures.user_fixture(preload: [:account])
      account = user.account

      event = %Stripe.Event{
        type: "customer.updated",
        data: %{
          object: %Stripe.Customer{
            id: account.customer_id,
            email: "new-billing-email@example.com"
          }
        }
      }

      assert :ok = BillingController.handle_event(event)

      {:ok, updated_account} = Accounts.get_account_by_id(account.id)
      assert updated_account.billing_email == "new-billing-email@example.com"
    end

    test "keeps the billing email when the customer no longer has an email" do
      user = AccountsFixtures.user_fixture(preload: [:account])
      account = user.account

      event = %Stripe.Event{
        type: "customer.updated",
        data: %{object: %Stripe.Customer{id: account.customer_id, email: nil}}
      }

      assert :ok = BillingController.handle_event(event)

      {:ok, updated_account} = Accounts.get_account_by_id(account.id)
      assert updated_account.billing_email == account.billing_email
    end

    test "does not acknowledge a failed billing email update for a known customer" do
      user = AccountsFixtures.user_fixture(preload: [:account])
      account = user.account

      event = %Stripe.Event{
        type: "customer.updated",
        data: %{object: %Stripe.Customer{id: account.customer_id, email: "new-billing-email@example.com"}}
      }

      Mimic.expect(Accounts, :update_account, fn found_account, attrs ->
        assert found_account.id == account.id
        assert attrs == %{billing_email: "new-billing-email@example.com"}
        {:error, Ecto.Changeset.change(found_account)}
      end)

      assert_raise MatchError, fn -> BillingController.handle_event(event) end
    end

    test "reports customers Tuist created that no account is linked to" do
      expect(Sentry, :capture_message, fn _message, _opts -> {:ok, ""} end)

      event = %Stripe.Event{
        type: "customer.updated",
        data: %{
          object: %Stripe.Customer{
            id: "cus_unknown_#{System.unique_integer([:positive])}",
            email: "new-billing-email@example.com",
            metadata: %{"tuist_account_id" => "42"}
          }
        }
      }

      assert :ok = BillingController.handle_event(event)
    end
  end

  describe "handle_event/1" do
    test "tags the request's logs with the Stripe event and customer" do
      event = %Stripe.Event{
        id: "evt_123",
        type: "invoice.payment_failed",
        data: %{object: %Stripe.Invoice{id: "in_123", customer: "cus_123"}}
      }

      BillingController.handle_event(event)

      assert Logger.metadata()[:stripe_event_id] == "evt_123"
      assert Logger.metadata()[:stripe_event_type] == "invoice.payment_failed"
      assert Logger.metadata()[:stripe_customer_id] == "cus_123"
    end
  end

  describe "handle_event/1 for invoice.payment_failed" do
    test "queues the failed-payment email" do
      user = AccountsFixtures.user_fixture(customer_id: "cus_#{System.unique_integer([:positive])}", preload: [:account])

      event = %Stripe.Event{
        type: "invoice.payment_failed",
        data: %{
          object: %Stripe.Invoice{
            id: "in_failed",
            customer: user.account.customer_id,
            attempt_count: 1,
            billing_reason: "subscription_cycle",
            collection_method: "charge_automatically"
          }
        }
      }

      assert :ok = BillingController.handle_event(event)

      assert_enqueued(
        worker: PaymentFailedNotificationWorker,
        args: %{invoice_id: "in_failed", user_id: user.id}
      )
    end
  end

  describe "handle_event/1 for invoice.finalized" do
    defp invoice_event(type, invoice_id) do
      %Stripe.Event{type: type, data: %{object: %Stripe.Invoice{id: invoice_id}}}
    end

    # A renewal carrying standing prepaid minutes is finalized about an hour
    # after the period opens, however late it is later paid.
    test "enqueues the grant when an invoice is finalized" do
      invoice_id = "in_#{System.unique_integer([:positive])}"

      assert :ok = BillingController.handle_event(invoice_event("invoice.finalized", invoice_id))

      assert_enqueued(worker: CreateRunnerPrepaidGrantWorker, args: %{invoice_id: invoice_id})
    end

    test "does not enqueue a second grant when the finalized invoice is paid" do
      invoice_id = "in_#{System.unique_integer([:positive])}"

      assert :ok = BillingController.handle_event(invoice_event("invoice.finalized", invoice_id))
      assert :ok = BillingController.handle_event(invoice_event("invoice.paid", invoice_id))

      assert [_one] = all_enqueued(worker: CreateRunnerPrepaidGrantWorker)
    end
  end

  describe "handle_event/1 for invoice.paid" do
    defp invoice_paid do
      %Stripe.Event{
        type: "invoice.paid",
        data: %{object: %Stripe.Invoice{id: "in_#{System.unique_integer([:positive])}"}}
      }
    end

    # The payload carries at most the first handful of an invoice's
    # lines, so the controller cannot tell a prepaid invoice from an
    # ordinary one without truncating its view. It enqueues for every
    # paid invoice and lets the worker page the lines and decide.
    test "enqueues for every paid invoice, so a prepaid line further down a bill is not missed" do
      event = invoice_paid()

      assert :ok = BillingController.handle_event(event)

      assert_enqueued(worker: CreateRunnerPrepaidGrantWorker, args: %{invoice_id: event.data.object.id})
    end

    test "enqueues once per invoice however many times Stripe redelivers" do
      event = invoice_paid()

      assert :ok = BillingController.handle_event(event)
      assert :ok = BillingController.handle_event(event)

      assert [_one] = all_enqueued(worker: CreateRunnerPrepaidGrantWorker)
    end
  end
end
