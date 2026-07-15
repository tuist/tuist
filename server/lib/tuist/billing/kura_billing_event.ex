defmodule Tuist.Billing.KuraBillingEvent do
  @moduledoc """
  Records Kura usage events that have been reported to Stripe.
  """
  use Ecto.Schema

  alias Tuist.Accounts.Account

  @primary_key {:event_id, :string, autogenerate: false}
  schema "kura_billing_events" do
    field :reported_at, :utc_datetime

    belongs_to :account, Account
  end
end
