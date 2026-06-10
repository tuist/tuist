defmodule Tuist.Accounts.AuthenticatedService do
  @moduledoc """
  Authenticated machine-to-machine OAuth client.

  Service subjects are not tied to a customer account. They are intended for
  trusted integrations that need explicitly scoped cross-account access.
  """

  @enforce_keys [:client_id, :scopes]
  defstruct [:client_id, :scopes]
end
