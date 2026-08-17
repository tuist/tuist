# Tuist App Logging

This target owns persistent logging for the Tuist companion app and produces support-safe log exports.

## Guardrails

- Route application messages through `Logger.current` so Pulse captures them consistently.
- Keep exports free of credentials and other authentication secrets.
- Bound on-device retention by both age and size.
- Keep log sharing contextual to errors or support flows rather than adding permanent diagnostics controls.
