defmodule Atlas.Orbit.ToolPolicy do
  @moduledoc """
  Default-deny allowlist of Atlas MCP tools the thread assistant may call.

  Every entry declares the scopes its output requires. Those scopes are the
  audience floor: the tool is offered only when every person who can read the
  thread holds them, and a successful call ratchets them onto the
  thread. The MCP tool still performs its own checks for the acting user.

  A tool's scopes must cover every area its output draws from, not only its
  primary one: `get_account` embeds contract-document service levels, so it
  requires `documents:read` as well as `accounts:read`.

  "Read-only" means no domain state changes: `ToolPolicyTest` executes every
  allowed tool and asserts it inserts, updates, or deletes no rows other than its
  own audit event. Semantic search tools still send the query to the operator's
  configured embedding provider.

  The first slice is read-only. Writes, sends, web egress, upstream MCP proxies,
  memory writes, raw SQL, and anything returning credentials, login handles,
  DSNs, license keys, or signed download URLs are never mounted. Tools whose
  output depends on per-call arguments that could widen the required access
  (federated search across document domains, for example) are excluded until
  the policy can pin those arguments.
  """

  alias Atlas.MCP.Server
  alias Atlas.MCP.Tool

  @accounts ["accounts:read"]
  @finance ["finance:read"]
  @engineering ["engineering:read"]
  @support ["support:read"]
  @gtm ["gtm:read"]
  @assets ["assets:read"]

  @policy %{
    # Embeds service levels extracted from contract documents.
    "get_account" => ["accounts:read", "documents:read"],
    "list_accounts" => @accounts,
    "list_account_contacts" => @accounts,
    "list_account_events" => @accounts,
    "list_account_terms" => @accounts,
    "list_account_feature_interests" => @accounts,
    "list_account_feature_usage" => @accounts,
    "get_account_feature_usage" => @accounts,
    "list_account_nudges" => @accounts,
    "list_upcoming_renewals" => @accounts,
    "get_event" => @accounts,
    "list_feature_interests" => @accounts,
    "get_feature_interest" => @accounts,
    "list_pocs" => @accounts,
    "get_poc" => @accounts,
    "list_account_service_levels" => ["accounts:read", "documents:read"],
    "list_account_incident_contacts" => ["accounts:read", "documents:read"],
    "search_documents" => ["documents:read"],
    "list_account_invoices" => ["accounts:read", "finance:read"],
    "list_invoices" => @finance,
    "get_finance_overview" => @finance,
    "get_finance_expense_history" => @finance,
    "get_finance_expense_reconciliation" => @finance,
    "list_finance_accounts" => @finance,
    "list_finance_categories" => @finance,
    "list_finance_invoices" => @finance,
    "get_monthly_invoice_totals" => @finance,
    "list_finance_transactions" => @finance,
    "list_notes" => ["notes:read"],
    "get_note" => ["notes:read"],
    "search_notes" => ["notes:read"],
    "list_tasks" => [],
    "list_people" => [],
    "list_engineering_projects" => @engineering,
    "get_engineering_project" => @engineering,
    "list_engineering_domains" => @engineering,
    "get_engineering_domain" => @engineering,
    "list_error_issues" => @engineering,
    "get_error_issue" => @engineering,
    "list_postmortems" => @engineering,
    "get_postmortem" => @engineering,
    "list_postmortem_action_items" => @engineering,
    "get_postmortem_action_item" => @engineering,
    "list_specs" => @engineering,
    "get_spec" => @engineering,
    "list_spec_comments" => @engineering,
    "list_support_threads" => @support,
    "get_support_thread" => @support,
    "list_gtm_opportunities" => @gtm,
    "get_gtm_opportunity" => @gtm,
    "list_gtm_advocates" => @gtm,
    "list_outreach_candidates" => @gtm,
    "list_outreach_contacts" => @gtm,
    "get_outreach_contact" => @gtm,
    "get_outreach_next_step" => @gtm,
    "list_blog_post_ideas" => @gtm,
    "get_blog_post_idea" => @gtm,
    "list_social_channel_ideas" => @gtm,
    "get_social_channel_idea" => @gtm,
    "list_social_post_revisions" => @gtm,
    "get_social_post_revision" => @gtm,
    "list_assets" => @assets,
    "get_asset" => @assets,
    "list_asset_assignments" => @assets,
    "list_asset_events" => @assets,
    "get_asset_book_value" => @assets,
    "list_data_centers" => @assets,
    "get_data_center" => @assets,
    "list_financings" => @assets,
    "get_financing" => @assets,
    "list_insurance_policies" => ["assets:read", "insurance:read"],
    "get_insurance_policy" => ["assets:read", "insurance:read"],
    "list_contract_templates" => ["contracts:read"],
    # Leadership reads. The MCP server additionally gates these behind
    # admin:read, so the audience floor includes it.
    "list_briefs" => ["briefs:read", "admin:read"],
    "get_brief" => ["briefs:read", "admin:read"],
    "list_audit_activities" => ["audit:read", "admin:read"],
    "get_audit_activity" => ["audit:read", "admin:read"]
  }

  # Categories that must never be mounted, kept explicit so a policy edit that
  # adds one fails `Atlas.Orbit.ToolPolicyTest`.
  @never [
    # Credentials and login handles.
    "connect_claude_provider",
    "start_chatgpt_provider_login",
    "poll_chatgpt_provider_login",
    "cancel_chatgpt_provider_login",
    "disconnect_llm_provider",
    "list_llm_provider_connections",
    # MCP and identity administration.
    "create_mcp_server",
    "delete_mcp_server",
    "get_mcp_connection_status",
    # Secrets, keys, and signed URLs.
    "get_domain_error_dsn",
    "get_project_error_dsn",
    "rotate_domain_error_dsn",
    "rotate_project_error_dsn",
    "list_licenses",
    "create_license",
    "extend_license",
    "check_out_air_gapped_license",
    "get_contract_template",
    "get_document",
    "list_documents",
    "create_document_upload",
    "finalize_document_upload",
    "create_letter_document_upload",
    "finalize_letter_document_upload",
    # Raw queries that bypass the scope model.
    "query_tuist_postgres",
    "query_tuist_clickhouse",
    # Network egress.
    "browse_url",
    "search_web",
    "search_apollo_outreach",
    # Shared memory is written by any MCP caller and by the Slack agent without
    # scopes, so neither reading nor writing it is audience-safe yet.
    "save_memory",
    "recall_memory",
    # Argument-dependent search.
    "search_atlas",
    # Writes on read: upserts and disables the research signal queries.
    "list_gtm_research_topics",
    # Viewer-dependent personal data.
    "get_time_off_overview",
    "get_time_off_calendar",
    # External side effects.
    "send_account_email",
    "send_email_broadcast",
    "send_nudge",
    "reply_to_support_thread",
    "upload_postal_letter",
    "request_tax_certificate_letter"
  ]

  def policy, do: @policy
  def never, do: @never

  def required_scopes(name) when is_binary(name), do: Map.fetch(@policy, name)

  @doc """
  Tool descriptors (`name`, `description`, `inputSchema`) offered to an audience
  holding `effective_scopes`, sorted by name.
  """
  def available(effective_scopes) do
    for module <- Server.tool_modules(),
        descriptor = Tool.descriptor(module),
        {:ok, scopes} <- [required_scopes(descriptor["name"])],
        Enum.all?(scopes, &MapSet.member?(effective_scopes, &1)) do
      Map.take(descriptor, ["name", "description", "inputSchema"])
    end
    |> Enum.sort_by(& &1["name"])
  end
end
