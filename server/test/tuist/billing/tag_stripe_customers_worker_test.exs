defmodule Tuist.Billing.Workers.TagStripeCustomersWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Billing.Workers.TagStripeCustomersWorker
  alias Tuist.Environment
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    stub(Environment, :stripe_configured?, fn -> true end)
    :ok
  end

  test "tags every linked Stripe customer with its account's id" do
    %{account: first} = AccountsFixtures.user_fixture(preload: [:account])
    %{account: second} = AccountsFixtures.user_fixture(preload: [:account])
    AccountsFixtures.user_fixture(customer_id: nil)
    test_pid = self()

    stub(Stripe.Customer, :update, fn customer_id, params ->
      send(test_pid, {:tagged, customer_id, params})
      {:ok, %Stripe.Customer{id: customer_id}}
    end)

    assert :ok = perform_job(TagStripeCustomersWorker, %{})

    first_customer_id = first.customer_id
    first_account_id = "#{first.id}"
    second_customer_id = second.customer_id
    second_account_id = "#{second.id}"

    assert_received {:tagged, ^first_customer_id, %{metadata: %{"tuist_account_id" => ^first_account_id}}}
    assert_received {:tagged, ^second_customer_id, %{metadata: %{"tuist_account_id" => ^second_account_id}}}
    refute_received {:tagged, _, _}
  end

  test "skips customers deleted in Stripe" do
    AccountsFixtures.user_fixture()

    stub(Stripe.Customer, :update, fn _customer_id, _params ->
      {:error,
       %Stripe.Error{
         source: :stripe,
         code: :invalid_request_error,
         message: "No such customer",
         extra: %{http_status: 404}
       }}
    end)

    assert :ok = perform_job(TagStripeCustomersWorker, %{})
  end

  test "fails so it's retried when a customer couldn't be tagged" do
    AccountsFixtures.user_fixture()

    stub(Stripe.Customer, :update, fn _customer_id, _params ->
      {:error, %Stripe.Error{source: :network, code: :network_error, message: "timeout"}}
    end)

    assert {:error, _} = perform_job(TagStripeCustomersWorker, %{})
  end

  test "does nothing when Stripe isn't configured" do
    AccountsFixtures.user_fixture()
    stub(Environment, :stripe_configured?, fn -> false end)
    reject(Stripe.Customer, :update, 2)

    assert :ok = perform_job(TagStripeCustomersWorker, %{})
  end
end
