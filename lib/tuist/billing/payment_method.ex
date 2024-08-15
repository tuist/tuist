defmodule Tuist.Billing.PaymentMethod do
  @moduledoc """
  A module that represents a payment method.
  """

  @enforce_keys [:id, :card, :type]
  defstruct [:id, :card, :type]
end
