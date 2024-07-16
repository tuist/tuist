defmodule Tuist.Billing.Customer do
  @moduledoc """
  A module that represents a billing customer.
  """

  @enforce_keys [:id, :email]
  defstruct [:id, :email]
end
