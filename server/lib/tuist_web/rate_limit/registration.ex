defmodule TuistWeb.RateLimit.Registration do
  @moduledoc false

  alias TuistWeb.RateLimit

  # A single-use Turnstile token still has to be solved per attempt, so replay
  # protection stays tight even at a comfortable per-session capacity. The
  # bucket is debited on every submit, and a first-try user often burns two
  # or three slots to typos alone (weak password, taken handle, taken email),
  # so the ceiling is picked to keep those recoverable without shipping a
  # per-error refund path.
  @capacity 10
  @refill_rate 1 / 300

  def hit(session_token) when is_binary(session_token) and session_token != "" do
    session_key = :sha256 |> :crypto.hash(session_token) |> Base.url_encode64(padding: false)

    RateLimit.hit(
      "registration:#{session_key}",
      algorithm: :token_bucket,
      refill_rate: @refill_rate,
      capacity: @capacity
    )
  end

  def hit(_session_token), do: {:error, :missing_session}
end
