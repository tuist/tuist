defmodule Condukt.Sandbox.NetworkPolicy.Context do
  @moduledoc """
  Snapshot of session state handed to a `Condukt.Sandbox.NetworkPolicy`
  `:decide` callback per outbound request.

  The runtime assembles this struct when an outbound connection falls
  through the static `allow` / `deny` rules to a `:decide` rule. It is
  the only context the decider sees: a decider cannot reach back into
  the session itself.

  Fields:

    * `:session_id` — the gated session's id.
    * `:recent_messages` — the last `:context_messages` messages from
      the session (the decide rule's option, default 5), oldest first.
      Redaction (`Condukt.Redactor`) is applied before they leave the
      session, so the decider sees whatever the rest of the system
      would.
    * `:request` — the `Condukt.Sandbox.NetworkPolicy.Request` the agent is about
      to make. Method, path, and request headers are populated where
      the sidecar derived them pre-decision. Body is not in the
      context (kept out to bound the decider's input cost).
    * `:metadata` — caller-supplied per-session metadata, set via the
      decide rule's `:context_metadata` option. Useful for user
      identity, tenant, session purpose, etc.
  """

  defstruct session_id: nil,
            recent_messages: [],
            request: nil,
            metadata: %{}
end
