# Agent execution boundary

Atlas uses Condukt for in-process model and tool execution, not remote coding
sessions. A release without Kubernetes sandbox infrastructure is supported by
these execution paths. This is not a claim that every optional integration is
ready for independent installation.

## Runtime and dependencies

- The pinned Condukt 1.13.0 defaults `use Condukt` and anonymous runs to
  `Condukt.AgentRuntimes.Native`. Sessions default to `Condukt.Sandbox.Local`.
  That object accesses the local filesystem; it is not a security isolation
  boundary and does not provision a container or VM.
- Atlas does not select Kubernetes, Microsandbox, Virtual, Codex, or Claude Code
  runtimes, add Condukt coding tools, or provide sandbox credentials. Inspect
  session-option overrides as well as agent callbacks when adding a workflow.
- Condukt starts session stores and supervisors, including an idle Kubernetes
  network-policy control-channel supervisor. No cluster connection or sandbox
  starts just because that supervisor exists. Its transitive K8s package and
  precompiled native libraries remain build dependencies; this inventory does
  not remove them or claim native-free packaging.
- `Atlas.LLMs.Runner` builds model client options. Local mode dispatches through
  `Atlas.LLMs.LocalTransport` to Atlas' inference relay in-process; the relay
  can still call an explicitly configured external model provider. Remote
  model HTTP requests are not remote code execution.
- `Atlas.Agents.Sessions` wraps native runs and operations with persisted
  session records. Streaming Slack callers use `with_session/4` and transient
  Condukt sessions. Telemetry persists their audit trail.

## Call-site inventory

Paths in this table are relative to `lib/atlas/`. All are native execution.

| Entry points | Model/tool work |
| --- | --- |
| `accounts/agents/{overview_summary_agent,outcome_proposal_agent,screenshot_note_agent}.ex` | Audited text/structured generation from supplied account data or images; no coding tools. |
| `accounts/agents/email_event_agent.ex` | Audited extraction with inline account lookup/update and event storage tools. |
| `accounts/agents/granola_meeting_agent.ex` | Anonymous structured run with inline account/contact/event tools. |
| `accounts/agents/{service_level_extraction_agent,invoice_paid_celebration_agent}.ex` | Anonymous structured extraction or copy generation; no domain tools. |
| `documents/agents/document_classifier_agent.ex` | Audited classification with inline document-type and correspondent tools. |
| `finance/agents/invoice_extractor_agent.ex` | Audited structured invoice extraction; no domain tools. |
| `finance/agents/payment_detection_agent.ex` | Anonymous structured run with inline account search/context tools. |
| `finance/agents/{cost_digest_agent,weekly_summary_agent}.ex` | Anonymous structured reporting with inline finance queries. |
| `finance/categorization.ex` | Anonymous structured run with inline web search and category/transaction tools. |
| `letters/agents/delivery_address_agent.ex` | Audited extraction after storage download and local text extraction; no agent tools. `delivery_details_agent.ex` delegates here. |
| `outreach/agents/recommendation_agent.ex` | Audited drafting with inline public-research/message-learning tools. |
| `support_inbox/agents/classifier_agent.ex` | Audited structured classification with inline support-thread and transaction queries. |
| `memory/{edge_classifier,bulletin_synthesizer}.ex` | Audited classification/synthesis from supplied memory data; no tools. |
| `engineering/errors/agents/summary_agent.ex` | Audited structured operation over a bounded error snapshot; no domain tools. |
| `slack/{conversation_agent,conversation_responder}.ex` | Native streaming with inline account/content, search, memory, and MCP tools. Account/systems investigator subagents are native sessions with explicit tool lists, not coding agents. |
| `slack/mcp_tools.ex`, `memory/tools.ex`, `slack/url_content.ex` | Tool definitions, not remote runtimes. Atlas MCP calls run in-process with caller claims; optional proxy/provider calls retain their own transport and authorization. |

`Atlas.LLMs.RunnerTest` checks compiled production Condukt callbacks and the
anonymous-agent callbacks, rejects global runtime/sandbox/tool overrides and
separate MCP transports, scans all environment configuration sources for explicit
Condukt configuration, and checks declared default subagent options for coding
and command tools. `Atlas.Slack.ConversationAgentTest` also exercises call-time
Slack session options with populated systems-investigator tools. These are
callback/options checks, not proofs of every effective session or transport.
Anonymous call-time options and other execution overrides still require source
review. Existing runner tests exercise a real native model request against a fixture Plug without
an external model endpoint; Slack tests cover the in-process MCP bridge.

## Deployment implications

Manual records do not depend on model execution or Kubernetes sandbox access.
Model enrichment, browsing, storage/text extraction, Slack delivery, and external
MCP tools have separate dependencies. Do not infer that they are configured just
because native sessions can start. Inference's `coding` role authorizes model
relay requests; it does not launch coding workloads.

The Helm deployment disables automatic Kubernetes API token mounts and grants
no sandbox pod/exec RBAC. A separately projected Tuist-audience token remains
optional connector identity, not Kubernetes API access. Legacy sandbox namespace
retention and its staged cleanup are documented in
[`infra/helm/atlas/AGENTS.md`](../../../../infra/helm/atlas/AGENTS.md).

Any future remote coding workflow needs its own explicit capability, execution
isolation, credential/egress policy, audit, and deployment tests. Do not restore
blanket pod/exec permissions for ordinary model/tool workflows.
