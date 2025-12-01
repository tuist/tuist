defmodule Cache.Guardian do
  @moduledoc """
  Guardian configuration for JWT verification in the cache service.
  This module verifies JWTs signed by the main Tuist server.
  """

  use Guardian, otp_app: :cache

  def subject_for_token(_resource, %{"sub" => sub}) do
    {:ok, sub}
  end

  def resource_from_claims(_claims) do
    # Not used for verification-only use case
    {:error, :not_implemented}
  end
end
