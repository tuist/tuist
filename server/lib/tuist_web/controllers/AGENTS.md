# Controllers (Web Layer)

This area owns Phoenix controllers for HTML and API endpoints.

## Responsibilities
- Handle request/response flow and rendering for controller actions.
- Delegate business logic to `server/lib/tuist` contexts.
- Keep the machine-readable auth.md document, discovery metadata, and agent-auth response envelopes synchronized when the protocol surface changes.

## Boundaries
- Domain logic belongs in `server/lib/tuist` contexts.
- Frontend assets are in `server/assets`.

## Related Context
- Web layer overview: `server/lib/tuist_web/AGENTS.md`
- Business logic: `server/lib/tuist/AGENTS.md`

- Command event schemas accept effective destinations and individual subhashes, including embedded products, foreign builds, and UI-test device/runtime inputs. Module-cache responses expose null for unavailable typed inputs and omit unavailable subhashes to preserve the existing string-valued map contract.
