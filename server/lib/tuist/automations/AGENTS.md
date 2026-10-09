# Automations

Project settings share test-case and build automation configuration, actions, and edit history.

- Test metric monitors use their existing ClickHouse per-test trigger/recovery ledger and baseline workers. Do not route build monitors through that lifecycle.
- Build automations use the `cache_key_consistency` monitor with no condition options, one Slack action, and no recovery. The scheduler dispatches it through the dedicated `BuildAlertEvaluationWorker`/`build_automation_evaluations` queue, not the test alert queue.
- Build detection and persistent findings: [builds/AGENTS.md](builds/AGENTS.md).
- Slack messages must escape customer-provided values. A failed build notification, including absent Slack credentials, must remain pending for retry.
- Authorization belongs at the API/dashboard boundary; rule history excludes encrypted Slack webhook credentials.
