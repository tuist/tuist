# WebSock Bridges (Web Layer)

- Validate that controller-upgraded sessions are scoped and authorized before moving bytes.
- Keep transport credentials and infrastructure addresses out of browser-facing payloads.
- Delegate lifecycle and authorization state to `server/lib/tuist` contexts.
- Keep route-level authentication and upgrade decisions in controllers.
- `TuistWeb.SandboxNodeWebSock` is the one node-facing socket here: sandboxd daemons connect through `TuistWeb.SandboxNodesController`; the socket tracks the node in `Tuist.Sandboxes.NodePresence`, subscribes to the node's `Tuist.PubSub` topic and bridges the `Tuist.Sandboxes.Nodes.call/4` commands broadcast there (from any web replica) to the node (see `server/lib/tuist/sandboxes/AGENTS.md`).
