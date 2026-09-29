# Complete server cluster verification

- Follow `README.md` for dedicated service setup and execution. This is a standalone verification harness, not an automatically discovered ExUnit suite.
- Keep two ordinary full application processes behind the round-robin proxy. Do not replace request paths, storage, rendering, or admission with mocks.
- Preserve the hidden observer, actual address records, fixed distribution listeners, and documented differences from deployed pod networking and production ingestion.
- Use only disposable local databases and dedicated object-storage and limiter services. Never pause a shared limiter or terminate a process not owned by this run.
- Keep screenshot generation bounded and collect assertion-only output for review. Diagnostic server logs can contain synthetic credentials.
