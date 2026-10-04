defmodule Tuist.Billing.Workers.TagStripeCustomersWorker do
  @moduledoc """
  Tags the Stripe customer of every account with the account's id, the tag
  `Tuist.Billing.create_customer/1` sets on new customers. Runs weekly so that
  customers created before the tag existed, or linked to an account any other
  way, carry it too.

  Stripe merges metadata keys, so other keys on the customer are kept and
  already-tagged customers are rewritten with the same value.
  """
  use Oban.Worker

  import Ecto.Query, only: [from: 2]

  alias Tuist.Accounts.Account
  alias Tuist.Billing
  alias Tuist.Environment
  alias Tuist.Repo

  require Logger

  @impl Oban.Worker
  def perform(_job) do
    if Environment.stripe_configured?() do
      failures =
        from(a in Account, where: not is_nil(a.customer_id), select: {a.id, a.customer_id}, order_by: a.id)
        |> Repo.all()
        |> Enum.reject(fn {account_id, customer_id} -> tag(account_id, customer_id) end)

      if failures == [], do: :ok, else: {:error, "#{length(failures)} Stripe customers could not be tagged"}
    else
      :ok
    end
  end

  defp tag(account_id, customer_id) do
    case Stripe.Customer.update(customer_id, %{metadata: Billing.customer_metadata(account_id)}) do
      {:ok, _customer} ->
        true

      # Deleted in Stripe: there is nothing left to tag.
      {:error, %Stripe.Error{extra: %{http_status: 404}}} ->
        true

      {:error, error} ->
        Logger.warning("Could not tag Stripe customer #{customer_id} of account #{account_id}: #{inspect(error)}")
        false
    end
  end
end
