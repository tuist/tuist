defmodule TuistWeb.SignupProtection do
  @moduledoc false

  alias TuistWeb.RateLimit.Registration
  alias TuistWeb.Turnstile

  def verify(session_token, params, expected_action) do
    if Turnstile.required?() do
      with {:allow, _count} <- Registration.hit(session_token),
           :ok <- Turnstile.verify(Map.get(params, "cf-turnstile-response"), expected_action: expected_action) do
        :ok
      else
        {:deny, _limit} -> {:error, :rate_limited}
        {:error, :missing_session} -> {:error, :missing_session}
        {:error, _reason} -> {:error, :turnstile_failed}
      end
    else
      :ok
    end
  end
end
