defmodule Tuist.Accounts.AuthenticatedAccount do
  @moduledoc """
  This module defines an authenticated account.
  """
  @enforce_keys [:account, :scopes]
  defstruct [:account, :scopes]
end
