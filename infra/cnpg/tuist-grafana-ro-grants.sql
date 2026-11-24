-- Per-column privileges for the `tuist_grafana_ro` role.
--
-- This role backs the Grafana "Tuist Product Usage" dashboard and the
-- "Runner cache volume warm rate low" alert rule, plus runner lifecycle
-- incident queries, which reach CNPG over the
-- PDC tunnel (see infra/helm/tuist/templates/pdc-agent.yaml). Its
-- password lives in Grafana Cloud, so it is the one database credential we hand
-- to a third party — it gets the narrowest grant set that still renders the
-- dashboard, alerts and incident queries, and nothing else.
--
-- Deliberately NOT `pg_read_all_data` (which is what `tuist_ops_ro` uses): every
-- table this dashboard reads sits next to a secret in the same row, so even
-- table-level SELECT would over-grant. Concretely, table-level SELECT would
-- expose `users.encrypted_password`, `users.reset_password_token`,
-- `projects.slack_webhook_url`, `accounts.s3_secret_access_key`,
-- and `organizations.oauth2_encrypted_client_secret`. Hence column-level grants.
--
-- The grants below are an exact allowlist of dashboard, alert and incident-query
-- columns. That is the point: adding a query column is a deliberate change
-- here, not something a dashboard edit silently widens. If a panel starts
-- erroring with "permission denied for table ...", a column is missing — add it
-- here rather than reaching for a broader grant.
--
-- `COUNT(*)` keeps working: PostgreSQL references no column for it and accepts
-- SELECT privilege on any one column of the table.

\if :{?tuist_schema}
\else
\set tuist_schema public
\endif

BEGIN;

GRANT CONNECT ON DATABASE tuist TO tuist_grafana_ro;
GRANT USAGE ON SCHEMA :"tuist_schema" TO tuist_grafana_ro;

-- accounts: identity + billing contact. Excludes the custom-storage credentials
-- (s3_access_key_id, s3_secret_access_key, s3_endpoint, s3_bucket_name) and
-- customer_id.
GRANT SELECT (
  id, name, billing_email, organization_id
) ON :"tuist_schema".accounts TO tuist_grafana_ro;

-- projects: identity + the Gradle build-system panels. Excludes the Slack webhook URLs.
GRANT SELECT (
  id, name, account_id, created_at, build_system
) ON :"tuist_schema".projects TO tuist_grafana_ro;

-- organizations: only the signup curve. Excludes the OAuth2 client secret.
GRANT SELECT (id, created_at) ON :"tuist_schema".organizations TO tuist_grafana_ro;

-- users: ONLY the signup timestamp. No email, no encrypted_password,
-- no reset/confirmation/unlock tokens, no sign-in IPs.
GRANT SELECT (created_at) ON :"tuist_schema".users TO tuist_grafana_ro;

-- subscriptions: just enough to tell subscribed from not. Excludes
-- default_payment_method and subscription_id.
GRANT SELECT (account_id, status) ON :"tuist_schema".subscriptions TO tuist_grafana_ro;

-- previews / bundles: the per-feature usage aggregations.
GRANT SELECT (project_id, inserted_at) ON :"tuist_schema".previews TO tuist_grafana_ro;
GRANT SELECT (project_id, inserted_at, git_ref) ON :"tuist_schema".bundles TO tuist_grafana_ro;

-- roles / users_roles: organization member counts.
GRANT SELECT (id, resource_id, resource_type) ON :"tuist_schema".roles TO tuist_grafana_ro;
GRANT SELECT (user_id, role_id) ON :"tuist_schema".users_roles TO tuist_grafana_ro;

-- runner cache volumes: the warm-rate alert rule (warm share of uses with a
-- saved copy, per platform, excluding test keys). Excludes account_id,
-- repository, pod_name and node_name.
GRANT SELECT (volume_id, base_generation, warm, attached_at) ON :"tuist_schema".runner_cache_volume_uses TO tuist_grafana_ro;
GRANT SELECT (id, key, platform) ON :"tuist_schema".runner_cache_volumes TO tuist_grafana_ro;

-- Runner lifecycle: queue timing and shape, live admission reservations and
-- limits, and historical sessions for limit-held exclusions after claims are
-- deleted. Excludes repository/branch metadata, execution_identity, logs and
-- transition-event payloads. Keep these column grants explicit, even on tables
-- whose current columns are all operational: future columns are not approved.
GRANT SELECT (
  workflow_job_id, account_id, fleet_name, status, conclusion, platform, vcpus,
  memory_gb, enqueued_at, claimed_at, executor_claimed_at, started_at, completed_at,
  pod_name, runner_name, executed_workflow_job_id
) ON :"tuist_schema".runner_workflow_jobs TO tuist_grafana_ro;
GRANT SELECT (
  pod_name, workflow_job_id, account_id, fleet_name, site, claimed_at, platform,
  vcpus, memory_gb, lifecycle_state, runner_name, executed_workflow_job_id,
  pod_missing_since
) ON :"tuist_schema".runner_claims TO tuist_grafana_ro;
GRANT SELECT (
  account_id, platform, vcpus, memory_gb, updated_at
) ON :"tuist_schema".runner_concurrency_limits TO tuist_grafana_ro;
GRANT SELECT (
  id, account_id, workflow_job_id, executed_workflow_job_id, fleet_name, platform,
  vcpus, memory_gb, started_at, ended_at, job_started_at, job_ended_at, pod_name,
  runner_name, node_name
) ON :"tuist_schema".runner_sessions TO tuist_grafana_ro;

-- Defense in depth: no writes, and no privileges on tables added in future
-- migrations (the opposite of pg_read_all_data, which would pick them up
-- automatically).
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON ALL TABLES IN SCHEMA :"tuist_schema" FROM tuist_grafana_ro;
ALTER DEFAULT PRIVILEGES IN SCHEMA :"tuist_schema"
  REVOKE SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON TABLES FROM tuist_grafana_ro;

COMMIT;

-- Sanity checks.
SELECT rolname, rolcanlogin, rolsuper, rolcreatedb, rolcreaterole
FROM pg_roles
WHERE rolname = 'tuist_grafana_ro';

-- Should list ONLY the columns granted above.
SELECT table_name, column_name, privilege_type
FROM information_schema.column_privileges
WHERE grantee = 'tuist_grafana_ro'
ORDER BY table_name, column_name;

-- Should be empty: the role must not inherit a read-everything role.
SELECT r.rolname AS member_of
FROM pg_auth_members m
JOIN pg_roles r ON r.oid = m.roleid
JOIN pg_roles g ON g.oid = m.member
WHERE g.rolname = 'tuist_grafana_ro';
