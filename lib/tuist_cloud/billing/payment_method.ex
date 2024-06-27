defmodule TuistCloud.Billing.PaymentMethod do
  @moduledoc """
  A module that represents a payment method.
  """

  @enforce_keys [:id, :card]
  defstruct [:id, :card]
end
