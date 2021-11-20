defmodule TuistCloud.Billing do
  @moduledoc """
  A module for operations related to billing.
  """

  alias TuistCloud.Environment
  alias TuistCloud.Accounts

  def create_customer(%{name: name, email: email}) do
    {:ok, customer} = Stripe.Customer.create(%{name: name, email: email})
    customer.id
  end

  def create_session(customer) do
    {:ok, session} = Stripe.BillingPortal.Session.create(%{customer: customer})
    session
  end

  def update_plan(%{status: status, customer: customer}) do
    account = Accounts.get_account_from_customer_id(customer)

    if status == "active" or status == "trialing" do
      Accounts.update_plan(account, :enterprise)
    else
      Accounts.update_plan(account, :none)
    end
  end

  def enabled? do
    Environment.stripe_configured?()
  end
end
