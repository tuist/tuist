defmodule Atlas.Integrations.SlackEvents do
  @moduledoc """
  Verifies and handles incoming Slack webhook events.
  """

  def verify_signature(raw_body, timestamp, signature, signing_secret) do
    base_string = "v0:#{timestamp}:#{raw_body}"

    expected =
      "v0=" <>
        (:crypto.mac(:hmac, :sha256, signing_secret, base_string) |> Base.encode16(case: :lower))

    if Plug.Crypto.secure_compare(expected, signature) do
      :ok
    else
      {:error, :invalid_signature}
    end
  end

  def handle_event(_event), do: :ignored
end
