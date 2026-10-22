alias Atlas.Automations.Contract
alias Atlas.Automations.LocalOperations
alias Atlas.MCP.Server
# Explicit reviewed capability mappings, not automatic runtime discovery.
spec = """
accounts accounts:read accounts.list list_accounts read
accounts accounts:read accounts.get get_account read
accounts accounts:write accounts.create create_account write
accounts accounts:write accounts.update update_account write
accounts accounts:write accounts.mark_not_account mark_account_not_account approved
accounts accounts:read accounts.contacts.list list_account_contacts read
accounts accounts:write accounts.contacts.create create_contact write
accounts accounts:write accounts.contacts.update update_contact write
accounts accounts:write accounts.notes.create create_account_note write
accounts accounts:read accounts.events.list list_account_events read
accounts accounts:read accounts.events.get get_event read
accounts accounts:read accounts.terms.list list_account_terms read
accounts accounts:write accounts.terms.create create_account_term write
accounts accounts:write accounts.terms.update update_account_term write
accounts accounts:write accounts.terms.delete delete_account_term approved
accounts accounts:read accounts.renewals.list list_upcoming_renewals read
accounts accounts:read accounts.feature_interests.list list_feature_interests read
accounts accounts:read accounts.feature_interests.get get_feature_interest read
accounts accounts:write accounts.feature_interests.create create_feature_interest write
accounts accounts:read accounts.feature_interests.for_account list_account_feature_interests read
accounts accounts:write accounts.feature_interests.record record_feature_interest write
accounts accounts:write accounts.feature_interests.update_context update_feature_interest_account_context write
accounts accounts:read accounts.service_levels.list list_account_service_levels read
accounts accounts:read accounts.incident_contacts.list list_account_incident_contacts read
accounts accounts:read accounts.pocs.list list_pocs read
accounts accounts:read accounts.pocs.get get_poc read
accounts accounts:write accounts.pocs.create create_poc write
accounts accounts:write accounts.pocs.update update_poc approved
accounts accounts:write accounts.pocs.delete delete_poc approved
accounts accounts:write accounts.pocs.context.set set_poc_context approved
accounts accounts:write accounts.pocs.features.add add_poc_scope_feature approved
accounts accounts:write accounts.pocs.features.remove remove_poc_scope_feature approved
accounts accounts:write accounts.pocs.timeline.add add_poc_timeline_entry approved
accounts accounts:write accounts.pocs.timeline.update update_poc_timeline_entry approved
accounts accounts:write accounts.pocs.timeline.delete delete_poc_timeline_entry approved
accounts accounts:write accounts.pocs.publish publish_poc approved
accounts accounts:write accounts.pocs.unpublish unpublish_poc approved
tasks authenticated tasks.list list_tasks read
tasks authenticated tasks.create create_task write
tasks authenticated tasks.update update_task write
tasks authenticated tasks.complete complete_task write
notes notes:read notes.list list_notes read
notes notes:read notes.get get_note read
notes notes:write notes.create create_note write
notes notes:write notes.update update_note write
assets assets:read assets.list list_assets read
assets assets:read assets.get get_asset read
assets assets:write assets.create create_asset write
assets assets:write assets.update edit_asset_metadata write
assets assets:write assets.delete delete_asset approved
assets assets:read assets.assignments.list list_asset_assignments read
assets assets:read assets.events.list list_asset_events read
assets assets:read assets.book_value.get get_asset_book_value read
assets assets:write assets.place_in_service place_asset_in_service write
assets assets:write assets.assign assign_asset write
assets assets:write assets.return return_asset write
assets assets:write assets.mark_in_repair mark_asset_in_repair write
assets assets:write assets.mark_repaired mark_asset_repaired write
assets assets:write assets.mark_lost mark_asset_lost write
assets assets:write assets.recover recover_asset write
assets assets:write assets.retire retire_asset approved
assets assets:write assets.dispose dispose_asset approved
assets assets:write assets.repairs.record record_asset_repair write
assets assets:write assets.incidents.record record_asset_incident write
assets assets:write assets.notes.record record_asset_note write
assets assets:write assets.warranty.extend record_asset_warranty_extension write
assets assets:write assets.return_to_lessor mark_asset_returned_to_lessor approved
assets assets:read assets.data_centers.list list_data_centers read
assets assets:read assets.data_centers.get get_data_center read
assets assets:write assets.data_centers.create create_data_center write
assets assets:write assets.data_centers.update edit_data_center write
assets assets:write assets.data_centers.decommission decommission_data_center approved
assets assets:write assets.data_centers.delete delete_data_center approved
assets assets:write assets.data_centers.install_asset install_asset_in_data_center write
assets assets:read assets.financings.list list_financings read
assets assets:read assets.financings.get get_financing read
assets assets:read assets.financings.for_asset list_asset_financings read
assets assets:write assets.financings.create create_financing write
assets assets:write assets.financings.update edit_financing_metadata write
assets assets:write assets.financings.delete delete_financing approved
assets assets:write assets.financings.lines.set set_financing_lines write
assets assets:write assets.financings.accounting.set set_financing_accounting_treatment write
assets assets:write assets.financings.schedule.import import_financing_schedule approved
assets assets:write assets.financings.payment.match match_financing_payment write
assets assets:write assets.financings.payment.edit edit_financing_payment_decomposition write
assets assets:write assets.financings.pay_off mark_financing_paid_off approved
assets assets:write assets.financings.exercise_purchase_option exercise_purchase_option approved
assets assets:write assets.financings.return return_financing approved
assets assets:write assets.financings.terminate terminate_financing approved
assets assets:write assets.financings.documents.attach attach_document_to_financing write
assets assets:write assets.financings.documents.detach detach_document_from_financing approved
insurance insurance:read insurance.policies.list list_insurance_policies read
insurance insurance:read insurance.policies.get get_insurance_policy read
insurance insurance:write insurance.policies.create create_insurance_policy write
insurance insurance:write insurance.policies.update edit_insurance_policy write
insurance insurance:write insurance.policies.delete delete_insurance_policy approved
insurance insurance:write insurance.policies.activate activate_insurance_policy approved
insurance insurance:write insurance.policies.expire expire_insurance_policy approved
insurance insurance:write insurance.policies.cancel cancel_insurance_policy approved
insurance insurance:write insurance.members.add add_asset_to_insurance write
insurance insurance:write insurance.members.remove remove_asset_from_insurance approved
insurance insurance:write insurance.members.update edit_insurance_member write
insurance insurance:write insurance.claims.create record_insurance_claim write
insurance insurance:write insurance.claims.update update_insurance_claim write
insurance insurance:write insurance.claims.assets.link link_asset_to_insurance_claim write
insurance insurance:write insurance.claims.assets.unlink unlink_asset_from_insurance_claim approved
insurance insurance:write insurance.policies.documents.attach attach_document_to_insurance_policy write
insurance insurance:write insurance.policies.documents.detach detach_document_from_insurance_policy approved
insurance insurance:write insurance.claims.documents.attach attach_document_to_insurance_claim write
insurance insurance:write insurance.claims.documents.detach detach_document_from_insurance_claim approved
engineering engineering:read engineering.projects.list list_engineering_projects read
engineering engineering:read engineering.projects.get get_engineering_project read
engineering engineering:write engineering.projects.create create_engineering_project write
engineering engineering:write engineering.projects.update update_engineering_project write
engineering engineering:write engineering.projects.delete delete_engineering_project approved
engineering engineering:read engineering.domains.list list_engineering_domains read
engineering engineering:read engineering.domains.get get_engineering_domain read
engineering engineering:write engineering.domains.create create_engineering_domain write
engineering engineering:write engineering.domains.update update_engineering_domain write
engineering engineering:write engineering.domains.delete delete_engineering_domain approved
engineering engineering:write engineering.projects.domains.link link_project_domain write
engineering engineering:write engineering.projects.domains.unlink unlink_project_domain approved
engineering engineering:write engineering.projects.repositories.link link_project_repository write
engineering engineering:write engineering.projects.repositories.unlink unlink_project_repository approved
engineering engineering:read engineering.errors.list list_error_issues read
engineering engineering:read engineering.errors.get get_error_issue read
engineering engineering:write engineering.errors.resolve resolve_error_issue write
engineering engineering:write engineering.errors.ignore ignore_error_issue write
engineering engineering:read engineering.specs.list list_specs read
engineering engineering:read engineering.specs.get get_spec read
engineering engineering:write engineering.specs.create create_spec approved
engineering engineering:write engineering.specs.update update_spec approved
engineering engineering:write engineering.specs.delete delete_spec approved
engineering engineering:read engineering.specs.comments.list list_spec_comments read
engineering engineering:write engineering.specs.comments.create add_spec_comment write
engineering engineering:write engineering.specs.comments.update update_spec_comment write
engineering engineering:write engineering.specs.comments.delete delete_spec_comment approved
engineering engineering:read engineering.postmortems.list list_postmortems read
engineering engineering:read engineering.postmortems.get get_postmortem read
engineering engineering:write engineering.postmortems.create create_postmortem write
engineering engineering:write engineering.postmortems.update update_postmortem write
engineering engineering:write engineering.postmortems.delete delete_postmortem approved
engineering engineering:read engineering.postmortems.items.list list_postmortem_action_items read
engineering engineering:read engineering.postmortems.items.get get_postmortem_action_item read
engineering engineering:write engineering.postmortems.items.create create_postmortem_action_item write
engineering engineering:write engineering.postmortems.items.update update_postmortem_action_item write
engineering engineering:write engineering.postmortems.items.delete delete_postmortem_action_item approved
finance finance:read finance.overview.get get_finance_overview read
finance finance:read finance.accounts.list list_finance_accounts read
finance finance:read finance.categories.list list_finance_categories read
finance finance:read finance.invoices.list list_finance_invoices read
finance finance:read finance.account_invoices.list list_account_invoices read
finance finance:read finance.transactions.list list_finance_transactions read
finance finance:read finance.expenses.history get_finance_expense_history read
finance finance:read finance.expenses.reconcile get_finance_expense_reconciliation read
documents documents:read documents.list list_documents read
documents documents:read documents.get get_document read
contracts contracts:read contracts.templates.list list_contract_templates read
letters letters:read letters.for_account list_account_letters read
gtm gtm:read gtm.opportunities.list list_gtm_opportunities read
gtm gtm:read gtm.opportunities.get get_gtm_opportunity read
gtm gtm:write gtm.opportunities.review review_gtm_opportunity write
gtm gtm:read gtm.advocates.list list_gtm_advocates read
gtm gtm:read gtm.research_topics.list list_gtm_research_topics read
gtm gtm:read gtm.blog_ideas.list list_blog_post_ideas read
gtm gtm:read gtm.blog_ideas.get get_blog_post_idea read
gtm gtm:write gtm.blog_ideas.create create_blog_post_idea write
gtm gtm:write gtm.blog_ideas.comments.create create_blog_post_idea_comment write
gtm gtm:read gtm.social_ideas.list list_social_channel_ideas read
gtm gtm:read gtm.social_ideas.get get_social_channel_idea read
gtm gtm:write gtm.social_ideas.create create_social_channel_idea write
gtm gtm:write gtm.social_ideas.update update_social_channel_idea write
gtm gtm:write gtm.social_ideas.delete delete_social_channel_idea approved
gtm gtm:read gtm.social_revisions.list list_social_post_revisions read
gtm gtm:read gtm.social_revisions.get get_social_post_revision read
gtm gtm:write gtm.social_revisions.create create_social_post_revision approved
gtm gtm:write gtm.social_revisions.update update_social_post_revision approved
gtm gtm:write gtm.social_revisions.delete delete_social_post_revision approved
gtm gtm:read gtm.email.subscribers.list list_email_subscribers read
gtm gtm:write gtm.email.subscribers.create create_email_subscriber write
gtm gtm:write gtm.email.subscribers.update update_email_subscriber write
gtm gtm:read gtm.email.audiences.list list_email_audiences read
gtm gtm:read gtm.email.audiences.get get_email_audience read
gtm gtm:write gtm.email.audiences.create create_email_audience write
gtm gtm:write gtm.email.audiences.delete delete_email_audience approved
gtm gtm:write gtm.email.audiences.unsubscribe unsubscribe_email_audience_subscriber write
gtm gtm:read gtm.email.outbox.list list_email_outbox read
gtm gtm:read gtm.email.sent.get get_sent_email read
gtm gtm:read gtm.outreach.contacts.list list_outreach_contacts read
gtm gtm:read gtm.outreach.contacts.get get_outreach_contact read
gtm gtm:write gtm.outreach.events.record record_outreach_event write
gtm gtm:read gtm.outreach.candidates.list list_outreach_candidates read
gtm gtm:write gtm.outreach.candidates.reject reject_outreach_candidate write
gtm gtm:read gtm.outreach.next_step.get get_outreach_next_step read
gtm gtm:write gtm.outreach.next_step.complete complete_outreach_next_step approved
gtm gtm:write gtm.outreach.next_step.dismiss dismiss_outreach_next_step write
support support:read support.threads.list list_support_threads read
support support:read support.threads.get get_support_thread read
support support:write support.threads.update update_support_thread write
support support:write support.notes.create add_support_thread_note write
support support:read support.inbox.list list_email_inbox read
audit audit:read audit.activities.list list_audit_activities read
audit audit:read audit.activities.get get_audit_activity read
briefs briefs:read briefs.list list_briefs read
briefs briefs:read briefs.get get_brief read
briefs briefs:write briefs.items.act act_on_brief_item approved
engineering engineering:read engineering.claims.list list_cross_domain_claims read
engineering engineering:write engineering.claims.create create_cross_domain_claim write
engineering engineering:read product.traces.list list_product_traces read
"""

tools = Map.new(Server.static_tools(), &{&1.name(), &1})

{entries, rejected} =
  spec
  |> String.split("\n", trim: true)
  |> Enum.map(&String.split/1)
  |> Enum.reduce({[], %{}}, fn [domain, scope, name, tool, effect], {entries, rejected} ->
    module = Map.fetch!(tools, tool)
    input = Map.put(module.input_schema(), "additionalProperties", false)
    output = module.output_schema()
    permissions = if scope == "authenticated", do: [], else: [scope]
    permissions = Enum.uniq(Server.workflow_tool_scopes(module) ++ permissions)

    entry = %{
      "name" => name,
      "version" => if(name == "tasks.create", do: 2, else: 1),
      "handler" => Atom.to_string(module),
      "source_tool" => tool,
      "domain" => domain,
      "permissions" => permissions,
      "effect" => if(effect == "read", do: "read", else: "write"),
      "requires_approval" => effect == "approved",
      "execution_mode" => "local_transaction",
      "input_schema" => input,
      "output_schema" => output,
      "description" => module.description()
    }

    if Contract.validate_schema(input) == :ok and Contract.validate_schema(output) == :ok do
      {[entry | entries], rejected}
    else
      {entries,
       Map.put(
         rejected,
         tool,
         "The existing schema exceeds the bounded workflow contract; needs a smaller explicit projection."
       )}
    end
  end)

entries = Enum.sort_by(entries ++ LocalOperations.contracts(), &{&1["name"], &1["version"]})
allowed = MapSet.new(Enum.map(entries, & &1["source_tool"]))

excluded =
  Map.new(tools, fn {name, _} ->
    reason =
      cond do
        Map.has_key?(rejected, name) ->
          rejected[name]

        String.contains?(name, "automation") ->
          "Control-plane lifecycle operation; recursive workflow authoring/control is not a business behavior."

        name in ~w(list_licenses create_license extend_license get_contract_template) ->
          "Use the secret-free metadata behavior; this MCP result contains a credential or signed bearer URL."

        String.contains?(name, "dsn") or String.contains?(name, "mcp_server") or String.contains?(name, "webhook") or
            name == "check_out_air_gapped_license" ->
          "Credential or permission lifecycle is deliberately not a generic workflow capability."

        String.contains?(name, "tuist_postgres") or String.contains?(name, "tuist_clickhouse") ->
          "Remote arbitrary-query execution is outside bounded local domain actions."

        name in ~w(search_notes search_atlas recall_memory save_memory search_documents) ->
          "Vector/embedding effects need a bounded, durable operation-specific adapter; local list/get alternatives are available."

        name in ~w(send_account_email send_email_broadcast reply_to_support_thread add_email_audience_subscriber) ->
          "External delivery/outbox requires its own idempotency, approval and ambiguous-outcome conformance tests before workflow enablement."

        true ->
          "Provider/network/agent or integration-specific operation is not enabled in the transactional executor; requires an explicit bounded adapter and conformance fixtures."
      end

    {name, reason}
  end)
  |> Map.reject(fn {name, _} -> MapSet.member?(allowed, name) end)

policies = [
  %{
    domain: "accounts",
    policy:
      "Business CRUD and POC lifecycle use existing domain rules. Public-content edits/deletions require exact approval."
  },
  %{
    domain: "tasks",
    policy: "Shared teammate CRUD; v1 tasks.create remains unchanged and v2 exposes the complete task contract."
  },
  %{domain: "notes", policy: "Scoped CRUD with transactional search maintenance and post-commit vector jobs."},
  %{
    domain: "assets",
    policy: "Local asset, data-center and financing CRUD/transitions; destructive operations require exact approval."
  },
  %{
    domain: "insurance",
    policy:
      "Local policy/member/claim records; lifecycle/destructive operations require exact approval. No insurer API calls."
  },
  %{
    domain: "engineering",
    policy:
      "Projects/domains/specs/comments/postmortems/errors/claims/traces; never expose DSN secrets or arbitrary production queries."
  },
  %{
    domain: "finance",
    policy:
      "Normalized accounting reads only. Bank/provider-owned data and live attachment writes are not generic local CRUD."
  },
  %{
    domain: "documents",
    policy:
      "Stored metadata/extracted pages only. Upload credentials, object writes and provider processing require dedicated external adapters."
  },
  %{
    domain: "contracts",
    policy: "Shipped template metadata, without signed bearer download URLs or fabricated contract generation."
  },
  %{
    domain: "letters",
    policy:
      "Stored letter history only; paid postal submission, signing and storage require dedicated external adapters."
  },
  %{
    domain: "gtm",
    policy:
      "Local content, subscriber/audience, opportunity and outreach state. No automatic external send, prospect discovery or enrichment."
  },
  %{
    domain: "support",
    policy:
      "Conversation reads, assignment/status and internal notes. Outbound replies require a dedicated delivery adapter."
  },
  %{domain: "audit", policy: "Read-only evidence; no audit rewrite or deletion."},
  %{
    domain: "briefs",
    policy:
      "Read briefs and explicitly approve sensitive item actions. Agent-generated briefs remain outside local computation."
  },
  %{
    domain: "licenses",
    policy:
      "Credential-free metadata and approved issuance/extension. Never persist online keys or signed license artifacts as workflow outputs."
  },
  %{
    domain: "inference",
    policy:
      "Credential-free provider metadata and approved profile CRUD. No token issuance, role assignment, arbitrary endpoint configuration or LLM relay."
  },
  %{
    domain: "admin",
    policy:
      "Secret-free user/integration identity reads only; never automate grants, authentication credentials or private keys."
  },
  %{
    domain: "automation",
    policy:
      "Core computation only. Protected execution/source getters cannot be used to launder domain-scoped data into less-restricted workflows."
  }
]

path = "priv/automation/contracts/v1.json"

File.write!(
  path,
  Jason.encode!(%{"operations" => entries, "excluded_tools" => excluded, "domain_policies" => policies}, pretty: true) <>
    "\n"
)

IO.puts("Frozen #{length(entries)} domain operations; #{map_size(excluded)} explicitly excluded MCP operations.")
Enum.each(rejected, fn {name, reason} -> IO.puts("Projection needed: #{name}: #{reason}") end)
