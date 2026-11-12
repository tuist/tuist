defmodule Condukt.SessionID do
  @moduledoc """
  Generates UUIDv7 identifiers for `Condukt.Session` instances.

  UUIDv7 (RFC 9562) embeds a millisecond Unix timestamp in the high bits, so
  identifiers are roughly time-ordered: useful for index locality in
  downstream stores that persist session telemetry, and for human inspection.

  Callers that mint their own session ids (for example, to correlate a Condukt
  session with an external run record) can pass an `:id` option to
  `Condukt.start_link/2` and `Condukt.run/2` instead of generating one here.

  Generation is delegated to `Uniq.UUID.uuid7/0`.
  """

  @doc """
  Generates a new UUIDv7 string in canonical 8-4-4-4-12 lowercase hex form.
  """
  defdelegate generate, to: Uniq.UUID, as: :uuid7
end
