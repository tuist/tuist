# Http (Context)

- Keep server-owned Finch client metrics here.
- Reuse `tuist_common/lib/tuist_common/http` for shared Bandit/Thousand Island metrics and logging; shared transport observability belongs there, not in the server.
