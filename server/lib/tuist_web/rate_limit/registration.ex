defmodule TuistWeb.RateLimit.Registration do
  @moduledoc false

  alias TuistWeb.RateLimit

  @capacity 3
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

  def hit(_session_token), do: {:deny, 0}
end
