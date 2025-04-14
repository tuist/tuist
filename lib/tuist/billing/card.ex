defmodule Tuist.Billing.Card do
  @moduledoc """
  A module that represents a card.
  """

  @enforce_keys [:brand, :last4, :exp_month, :exp_year, :cardholder_name]
  defstruct [:brand, :last4, :exp_month, :exp_year, :cardholder_name]
end
