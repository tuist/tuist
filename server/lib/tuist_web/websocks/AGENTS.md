# WebSock Bridges (Web Layer)

- Validate that controller-upgraded sessions are scoped and authorized before moving bytes.
- Keep transport credentials and infrastructure addresses out of browser-facing payloads.
- Delegate lifecycle and authorization state to `server/lib/tuist` contexts.
- Keep route-level authentication and upgrade decisions in controllers.
