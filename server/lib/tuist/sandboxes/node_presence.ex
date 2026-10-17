defmodule Tuist.Sandboxes.NodePresence do
  @moduledoc """
  Cluster-wide presence of connected sandboxd nodes. Each
  `TuistWeb.SandboxNodeWebSock` tracks itself under its node name on the
  `"sandbox_nodes"` topic, so every web replica sees every node
  regardless of which replica holds the socket.

  A replica learns about the others from their heartbeats, and an idle
  tracker only sends one every `max_silent_periods` broadcast periods (15 s
  by default), so a replica that has just started could take that long to
  see any node. Heartbeating every 3 s keeps that gap short; `down_period`
  stays at the default 30 s so a replica is not dropped for a short stall.
  """
  use Phoenix.Presence,
    otp_app: :tuist,
    pubsub_server: Tuist.PubSub,
    broadcast_period: 1_500,
    max_silent_periods: 2,
    down_period: 30_000
end
