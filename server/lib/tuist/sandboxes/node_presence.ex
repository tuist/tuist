defmodule Tuist.Sandboxes.NodePresence do
  @moduledoc """
  Cluster-wide presence of connected sandboxd nodes. Each
  `TuistWeb.SandboxNodeWebSock` tracks itself under its node name on the
  `"sandbox_nodes"` topic, so every web replica sees every node
  regardless of which replica holds the socket.
  """
  use Phoenix.Presence, otp_app: :tuist, pubsub_server: Tuist.PubSub
end
