defmodule Tuist.Sandboxes.NodePresence do
  @moduledoc """
  Cluster-wide presence of connected sandboxd nodes. Each
  `TuistWeb.SandboxNodeWebSock` tracks itself under its node name on the
  `"sandbox_nodes"` topic, so every web replica sees every node
  regardless of which replica holds the socket.

  Another replica sees a node's report only once the tracker gossips it,
  which it does once per `broadcast_period`. Admission waits on that
  report: a resume that grows a node's carve-out waits for the daemon to
  report the new limit, and on any replica but the socket's a 1.5 s
  period (Phoenix's default) was most of a resume's admission time.
  Reports are rare (one every 30 s, or on a change), so a short period
  adds little traffic.

  A replica learns about the others from their heartbeats, and an idle
  tracker only sends one every `max_silent_periods` broadcast periods, so
  a replica that has just started could take that long to see any node.
  Heartbeating every 3 s keeps that gap short; `down_period` stays at the
  default 30 s so a replica is not dropped for a short stall.
  """
  use Phoenix.Presence,
    otp_app: :tuist,
    pubsub_server: Tuist.PubSub,
    broadcast_period: 200,
    max_silent_periods: 15,
    down_period: 30_000
end
