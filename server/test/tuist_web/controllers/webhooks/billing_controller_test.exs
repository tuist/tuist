defmodule TuistWeb.Webhooks.BillingControllerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Accounts
  alias Tuist.Billing.Workers.PaymentFailedNotificationWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.Webhooks.BillingController

  describe "handle_event/1 for customer.updated" do
    test "acknowledges repeated updates for an unknown customer without changing another account" do
      user = AccountsFixtures.user_fixture(preload: [:account])
      account = user.account

      event = %Stripe.Event{
        type: "customer.updated",
        data: %{
          object: %{
            id: "cus_unknown_#{System.unique_integer([:positive])}",
            email: "unknown-customer@example.com"
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
          object: %{
            id: account.customer_id,
            email: "new-billing-email@example.com"
          }
        }
      }

      assert :ok = BillingController.handle_event(event)

      {:ok, updated_account} = Accounts.get_account_by_id(account.id)
      assert updated_account.billing_email == "new-billing-email@example.com"
    end

    test "does not acknowledge a failed billing email update for a known customer" do
      user = AccountsFixtures.user_fixture(preload: [:account])
      account = user.account

      event = %Stripe.Event{
        type: "customer.updated",
        data: %{object: %{id: account.customer_id, email: "new-billing-email@example.com"}}
      }

      Mimic.expect(Accounts, :update_account, fn found_account, attrs ->
        assert found_account.id == account.id
        assert attrs == %{billing_email: "new-billing-email@example.com"}
        {:error, Ecto.Changeset.change(found_account)}
      end)

      assert_raise MatchError, fn -> BillingController.handle_event(event) end
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

  describe "handle_event/1 for invoice.finalized and invoice.paid" do
    test "acknowledges the events without enqueuing any work" do
      for type <- ["invoice.finalized", "invoice.paid"] do
        event = %Stripe.Event{
          type: type,
          data: %{object: %Stripe.Invoice{id: "in_#{System.unique_integer([:positive])}"}}
        }

        assert :ok = BillingController.handle_event(event)
      end

      assert all_enqueued() == []
    end
  end
end
