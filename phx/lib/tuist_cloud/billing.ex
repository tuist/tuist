defmodule TuistCloud.Billing do
  @moduledoc """
  A module for operations related to billing.
  """

  alias TuistCloud.Environment

  def create_customer(opts) do
    name = opts |> Keyword.get(:name)
    email = opts |> Keyword.get(:email)
    {:ok, customer} = Stripe.Customer.create(%{name: name, email: email})
    customer.id
  end

  def create_session(opts) do
    customer = opts |> Keyword.get(:customer)
    {:ok, session} = Stripe.BillingPortal.Session.create(%{customer: customer})
    session
  end

  def enabled? do
    Environment.stripe_configured?()
  end
end
