defmodule Tuist.Authentication.UnavailableError do
  @moduledoc """
  Authentication could not complete. This is not a credential mismatch and must
  be rendered as unavailable, without bypassing cache failure guards with bcrypt.
  """
  defexception message: "Authentication temporarily unavailable.", plug_status: 503
end
