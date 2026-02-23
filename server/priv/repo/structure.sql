--
-- PostgreSQL database dump
--

-- Dumped from database version 17.5 (Homebrew)
-- Dumped by pg_dump version 17.2

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: citext; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA public;


--
-- Name: EXTENSION citext; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION citext IS 'data type for case-insensitive character strings';


--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: oban_job_state; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.oban_job_state AS ENUM (
    'available',
    'scheduled',
    'executing',
    'retryable',
    'completed',
    'discarded',
    'cancelled'
);


--
-- Name: oban_count_estimate(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.oban_count_estimate(state text, queue text) RETURNS integer
    LANGUAGE plpgsql
    AS $_$
DECLARE
  plan jsonb;
BEGIN
  EXECUTE 'EXPLAIN (FORMAT JSON)
           SELECT id
           FROM public.oban_jobs
           WHERE state = $1::public.oban_job_state
           AND queue = $2'
    INTO plan
    USING state, queue;
  RETURN plan->0->'Plan'->'Plan Rows';
END;
$_$;


--
-- Name: que_validate_tags(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.que_validate_tags(tags_array jsonb) RETURNS boolean
    LANGUAGE sql
    AS $$
  SELECT bool_and(
    jsonb_typeof(value) = 'string'
    AND
    char_length(value::text) <= 100
  )
  FROM jsonb_array_elements(tags_array)
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: que_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.que_jobs (
    priority smallint DEFAULT 100 NOT NULL,
    run_at timestamp with time zone DEFAULT now() NOT NULL,
    id bigint NOT NULL,
    job_class text NOT NULL,
    error_count integer DEFAULT 0 NOT NULL,
    last_error_message text,
    queue text DEFAULT 'default'::text NOT NULL,
    last_error_backtrace text,
    finished_at timestamp with time zone,
    expired_at timestamp with time zone,
    args jsonb DEFAULT '[]'::jsonb NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    job_schema_version integer NOT NULL,
    kwargs jsonb DEFAULT '{}'::jsonb NOT NULL,
    CONSTRAINT error_length CHECK (((char_length(last_error_message) <= 500) AND (char_length(last_error_backtrace) <= 10000))),
    CONSTRAINT job_class_length CHECK ((char_length(
CASE job_class
    WHEN 'ActiveJob::QueueAdapters::QueAdapter::JobWrapper'::text THEN ((args -> 0) ->> 'job_class'::text)
    ELSE job_class
END) <= 200)),
    CONSTRAINT queue_length CHECK ((char_length(queue) <= 100)),
    CONSTRAINT valid_args CHECK ((jsonb_typeof(args) = 'array'::text)),
    CONSTRAINT valid_data CHECK (((jsonb_typeof(data) = 'object'::text) AND ((NOT (data ? 'tags'::text)) OR ((jsonb_typeof((data -> 'tags'::text)) = 'array'::text) AND (jsonb_array_length((data -> 'tags'::text)) <= 5) AND public.que_validate_tags((data -> 'tags'::text))))))
)
WITH (fillfactor='90');


--
-- Name: TABLE que_jobs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.que_jobs IS '7';


--
-- Name: que_determine_job_state(public.que_jobs); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.que_determine_job_state(job public.que_jobs) RETURNS text
    LANGUAGE sql
    AS $$
  SELECT
    CASE
    WHEN job.expired_at  IS NOT NULL    THEN 'expired'
    WHEN job.finished_at IS NOT NULL    THEN 'finished'
    WHEN job.error_count > 0            THEN 'errored'
    WHEN job.run_at > CURRENT_TIMESTAMP THEN 'scheduled'
    ELSE                                     'ready'
    END
$$;


--
-- Name: que_job_notify(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.que_job_notify() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
  DECLARE
    locker_pid integer;
    sort_key json;
  BEGIN
    -- Don't do anything if the job is scheduled for a future time.
    IF NEW.run_at IS NOT NULL AND NEW.run_at > now() THEN
      RETURN null;
    END IF;

    -- Pick a locker to notify of the job's insertion, weighted by their number
    -- of workers. Should bounce pseudorandomly between lockers on each
    -- invocation, hence the md5-ordering, but still touch each one equally,
    -- hence the modulo using the job_id.
    SELECT pid
    INTO locker_pid
    FROM (
      SELECT *, last_value(row_number) OVER () + 1 AS count
      FROM (
        SELECT *, row_number() OVER () - 1 AS row_number
        FROM (
          SELECT *
          FROM public.que_lockers ql, generate_series(1, ql.worker_count) AS id
          WHERE
            listening AND
            queues @> ARRAY[NEW.queue] AND
            ql.job_schema_version = NEW.job_schema_version
          ORDER BY md5(pid::text || id::text)
        ) t1
      ) t2
    ) t3
    WHERE NEW.id % count = row_number;

    IF locker_pid IS NOT NULL THEN
      -- There's a size limit to what can be broadcast via LISTEN/NOTIFY, so
      -- rather than throw errors when someone enqueues a big job, just
      -- broadcast the most pertinent information, and let the locker query for
      -- the record after it's taken the lock. The worker will have to hit the
      -- DB in order to make sure the job is still visible anyway.
      SELECT row_to_json(t)
      INTO sort_key
      FROM (
        SELECT
          'job_available' AS message_type,
          NEW.queue       AS queue,
          NEW.priority    AS priority,
          NEW.id          AS id,
          -- Make sure we output timestamps as UTC ISO 8601
          to_char(NEW.run_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS run_at
      ) t;

      PERFORM pg_notify('que_listener_' || locker_pid::text, sort_key::text);
    END IF;

    RETURN null;
  END
$$;


--
-- Name: que_scheduler_check_job_exists(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.que_scheduler_check_job_exists() RETURNS boolean
    LANGUAGE sql
    AS $$
SELECT EXISTS(SELECT * FROM que_jobs WHERE job_class = 'Que::Scheduler::SchedulerJob');
$$;


--
-- Name: que_scheduler_prevent_job_deletion(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.que_scheduler_prevent_job_deletion() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
BEGIN
    IF OLD.job_class = 'Que::Scheduler::SchedulerJob' THEN
        IF NOT que_scheduler_check_job_exists() THEN
            raise exception 'Deletion of que_scheduler job prevented. Deleting the que_scheduler job is almost certainly a mistake.';
        END IF;
    END IF;
    RETURN OLD;
END;
$$;


--
-- Name: que_state_notify(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.que_state_notify() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
  DECLARE
    row record;
    message json;
    previous_state text;
    current_state text;
  BEGIN
    IF TG_OP = 'INSERT' THEN
      previous_state := 'nonexistent';
      current_state  := public.que_determine_job_state(NEW);
      row            := NEW;
    ELSIF TG_OP = 'DELETE' THEN
      previous_state := public.que_determine_job_state(OLD);
      current_state  := 'nonexistent';
      row            := OLD;
    ELSIF TG_OP = 'UPDATE' THEN
      previous_state := public.que_determine_job_state(OLD);
      current_state  := public.que_determine_job_state(NEW);

      -- If the state didn't change, short-circuit.
      IF previous_state = current_state THEN
        RETURN null;
      END IF;

      row := NEW;
    ELSE
      RAISE EXCEPTION 'Unrecognized TG_OP: %', TG_OP;
    END IF;

    SELECT row_to_json(t)
    INTO message
    FROM (
      SELECT
        'job_change' AS message_type,
        row.id       AS id,
        row.queue    AS queue,

        coalesce(row.data->'tags', '[]'::jsonb) AS tags,

        to_char(row.run_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS run_at,
        to_char(now()      AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS time,

        CASE row.job_class
        WHEN 'ActiveJob::QueueAdapters::QueAdapter::JobWrapper' THEN
          coalesce(
            row.args->0->>'job_class',
            'ActiveJob::QueueAdapters::QueAdapter::JobWrapper'
          )
        ELSE
          row.job_class
        END AS job_class,

        previous_state AS previous_state,
        current_state  AS current_state
    ) t;

    PERFORM pg_notify('que_state', message::text);

    RETURN null;
  END
$$;


--
-- Name: account_cache_endpoints; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.account_cache_endpoints (
    id uuid NOT NULL,
    account_id bigint NOT NULL,
    url character varying(255) NOT NULL,
    inserted_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: account_token_projects; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.account_token_projects (
    id uuid NOT NULL,
    account_token_id uuid NOT NULL,
    project_id bigint NOT NULL,
    inserted_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: account_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.account_tokens (
    id uuid NOT NULL,
    account_id bigint NOT NULL,
    encrypted_token_hash character varying(255) NOT NULL,
    inserted_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    name character varying(255),
    expires_at timestamp with time zone,
    created_by_account_id bigint,
    all_projects boolean DEFAULT true NOT NULL,
    scopes text[] DEFAULT '{}'::text[] NOT NULL
);


--
-- Name: accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounts (
    id bigint NOT NULL,
    name public.citext NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    customer_id character varying,
    user_id bigint,
    organization_id bigint,
    current_month_remote_cache_hits_count integer DEFAULT 0,
    current_month_remote_cache_hits_count_updated_at timestamp(0) without time zone,
    billing_email character varying(255) NOT NULL,
    namespace_tenant_id character varying(255),
    region integer DEFAULT 0 NOT NULL,
    s3_bucket_name character varying(255),
    s3_access_key_id bytea,
    s3_secret_access_key bytea,
    s3_region character varying(255),
    s3_endpoint character varying(255),
    custom_cache_endpoints_enabled boolean DEFAULT false NOT NULL
);


--
-- Name: accounts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounts_id_seq OWNED BY public.accounts.id;


--
-- Name: alert_rules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.alert_rules (
    id uuid NOT NULL,
    project_id bigint NOT NULL,
    name character varying(255) DEFAULT 'Untitled'::character varying NOT NULL,
    category integer NOT NULL,
    metric integer,
    deviation_percentage double precision NOT NULL,
    rolling_window_size integer,
    slack_channel_id character varying(255),
    slack_channel_name character varying(255),
    inserted_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    git_branch character varying(255),
    scheme character varying(255) DEFAULT ''::character varying NOT NULL,
    app_bundle_id character varying(255) DEFAULT ''::character varying NOT NULL
);


--
-- Name: alerts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.alerts (
    id uuid NOT NULL,
    alert_rule_id uuid NOT NULL,
    current_value double precision NOT NULL,
    previous_value double precision NOT NULL,
    inserted_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: app_builds; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.app_builds (
    id uuid NOT NULL,
    inserted_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    type integer,
    supported_platforms integer[] DEFAULT ARRAY[]::integer[],
    preview_id uuid,
    binary_id character varying(255),
    build_version character varying(255)
);


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: artifacts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.artifacts (
    id uuid NOT NULL,
    artifact_type character varying(255) NOT NULL,
    path character varying(255) NOT NULL,
    size integer NOT NULL,
    shasum character varying(255) NOT NULL,
    bundle_id uuid NOT NULL,
    artifact_id uuid,
    inserted_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: authorization_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.authorization_requests (
    id uuid NOT NULL,
    client_id character varying(255),
    client_authentication jsonb,
    response_type character varying(255),
    redirect_uri character varying(255),
    scope character varying(255),
    state character varying(255),
    code_challenge character varying(255),
    code_challenge_method character varying(255),
    expires_at integer,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: build_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.build_runs (
    id uuid NOT NULL,
    duration integer NOT NULL,
    project_id bigint NOT NULL,
    account_id bigint NOT NULL,
    macos_version character varying(255),
    xcode_version character varying(255),
    is_ci boolean NOT NULL,
    model_identifier character varying(255),
    scheme character varying(255),
    inserted_at timestamp with time zone NOT NULL,
    status integer,
    git_branch character varying(255),
    git_commit_sha character varying(255),
    category integer,
    git_ref character varying(255),
    configuration character varying(255),
    ci_run_id character varying(255),
    ci_project_handle character varying(255),
    ci_host character varying(255),
    ci_provider integer,
    cacheable_task_remote_hits_count integer DEFAULT 0 NOT NULL,
    cacheable_task_local_hits_count integer DEFAULT 0 NOT NULL,
    cacheable_tasks_count integer DEFAULT 0 NOT NULL,
    custom_tags character varying(255)[] DEFAULT ARRAY[]::character varying[],
    custom_values jsonb DEFAULT '{}'::jsonb
);


--
-- Name: bundles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bundles (
    id uuid NOT NULL,
    name character varying(255) NOT NULL,
    install_size integer NOT NULL,
    download_size integer,
    app_bundle_id character varying(255) NOT NULL,
    supported_platforms integer[] DEFAULT ARRAY[]::integer[],
    version character varying(255) NOT NULL,
    git_branch character varying(255),
    git_commit_sha character varying(255),
    uploaded_by_account_id bigint,
    project_id bigint NOT NULL,
    inserted_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    git_ref character varying(255),
    type integer DEFAULT 1 NOT NULL
);


--
-- Name: cache_action_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cache_action_items (
    id uuid NOT NULL,
    hash character varying(255) NOT NULL,
    project_id bigint NOT NULL,
    inserted_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: cache_endpoints; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cache_endpoints (
    id uuid NOT NULL,
    url character varying(255) NOT NULL,
    display_name character varying(255) NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    inserted_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: cache_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cache_events (
    id bigint NOT NULL,
    name character varying NOT NULL,
    event_type integer NOT NULL,
    size integer NOT NULL,
    project_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    hash character varying(255)
);


--
-- Name: cache_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.cache_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cache_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.cache_events_id_seq OWNED BY public.cache_events.id;


--
-- Name: oauth_clients_scopes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oauth_clients_scopes (
    id bigint NOT NULL,
    client_id uuid,
    scope_id uuid
);


--
-- Name: clients_scopes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.clients_scopes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: clients_scopes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.clients_scopes_id_seq OWNED BY public.oauth_clients_scopes.id;


--
-- Name: command_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.command_events (
    legacy_id bigint NOT NULL,
    name character varying,
    subcommand character varying,
    command_arguments character varying,
    duration integer,
    client_id character varying,
    tuist_version character varying,
    swift_version character varying,
    macos_version character varying,
    project_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    cacheable_targets character varying(255)[] DEFAULT '{}'::character varying[],
    local_cache_target_hits character varying(255)[] DEFAULT '{}'::character varying[],
    remote_cache_target_hits character varying(255)[] DEFAULT '{}'::character varying[],
    is_ci boolean DEFAULT false,
    status integer DEFAULT 0,
    error_message character varying(255),
    test_targets character varying(255)[],
    local_test_target_hits character varying(255)[],
    remote_test_target_hits character varying(255)[],
    user_id integer,
    remote_cache_target_hits_count integer DEFAULT 0,
    remote_test_target_hits_count integer DEFAULT 0,
    git_commit_sha character varying(255),
    git_ref character varying(255),
    preview_id uuid,
    git_branch character varying(255),
    ran_at timestamp with time zone,
    build_run_id uuid,
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL
);


--
-- Name: command_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.command_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: command_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.command_events_id_seq OWNED BY public.command_events.legacy_id;


--
-- Name: device_codes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.device_codes (
    id bigint NOT NULL,
    code character varying NOT NULL,
    authenticated boolean DEFAULT false,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    user_id bigint
);


--
-- Name: device_codes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.device_codes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: device_codes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.device_codes_id_seq OWNED BY public.device_codes.id;


--
-- Name: feature_flags; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.feature_flags (
    id uuid NOT NULL,
    flag_name character varying(255) NOT NULL,
    gate_type character varying(255) NOT NULL,
    target character varying(255) NOT NULL,
    enabled boolean NOT NULL
);


--
-- Name: github_app_installations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.github_app_installations (
    id uuid NOT NULL,
    account_id bigint NOT NULL,
    installation_id character varying(255) NOT NULL,
    html_url character varying(255),
    inserted_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: guardian_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.guardian_tokens (
    jti character varying(255) NOT NULL,
    aud character varying(255) NOT NULL,
    typ character varying(255),
    iss character varying(255),
    sub character varying(255),
    exp bigint,
    jwt text,
    claims jsonb,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: invitations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invitations (
    id bigint NOT NULL,
    inviter_type character varying NOT NULL,
    inviter_id bigint NOT NULL,
    invitee_email public.citext NOT NULL,
    organization_id bigint NOT NULL,
    token character varying(100) NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: invitations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.invitations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: invitations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.invitations_id_seq OWNED BY public.invitations.id;


--
-- Name: oauth2_identities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oauth2_identities (
    id bigint NOT NULL,
    provider integer DEFAULT 0 NOT NULL,
    user_id bigint NOT NULL,
    id_in_provider character varying NOT NULL,
    provider_organization_id character varying(255)
);


--
-- Name: oauth2_identities_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.oauth2_identities_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: oauth2_identities_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.oauth2_identities_id_seq OWNED BY public.oauth2_identities.id;


--
-- Name: oauth_clients; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oauth_clients (
    id uuid NOT NULL,
    name character varying(255) DEFAULT ''::character varying NOT NULL,
    secret character varying(255) NOT NULL,
    redirect_uris character varying(255)[] DEFAULT ARRAY[]::character varying[] NOT NULL,
    scope character varying(255),
    authorize_scope boolean DEFAULT false NOT NULL,
    supported_grant_types character varying(255)[] DEFAULT ARRAY['client_credentials'::text, 'password'::text, 'authorization_code'::text, 'refresh_token'::text, 'implicit'::text, 'revoke'::text, 'introspect'::text] NOT NULL,
    authorization_code_ttl integer NOT NULL,
    access_token_ttl integer NOT NULL,
    pkce boolean DEFAULT false NOT NULL,
    public_key text,
    private_key text NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    id_token_ttl integer DEFAULT 3600,
    public_refresh_token boolean DEFAULT false NOT NULL,
    refresh_token_ttl integer DEFAULT 2592000 NOT NULL,
    public_revoke boolean DEFAULT false NOT NULL,
    id_token_signature_alg character varying(255) DEFAULT 'RS512'::character varying,
    confidential boolean DEFAULT false NOT NULL,
    jwt_public_key text,
    token_endpoint_auth_methods character varying(255)[] DEFAULT ARRAY['client_secret_basic'::character varying, 'client_secret_post'::character varying] NOT NULL,
    token_endpoint_jwt_auth_alg character varying(255) DEFAULT 'HS256'::character varying NOT NULL,
    userinfo_signed_response_alg character varying(255),
    jwks_uri character varying(255),
    id_token_kid character varying(255),
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    logo_uri character varying(255),
    public_client_id character varying(255),
    enforce_dpop boolean DEFAULT false,
    authorization_request_ttl integer DEFAULT 60,
    did text,
    response_mode character varying(255) DEFAULT 'direct_post'::character varying,
    key_pair_type jsonb DEFAULT '{"type": "rsa", "modulus_size": "1024", "exponent_size": "65537"}'::jsonb,
    enforce_tx_code boolean DEFAULT false NOT NULL,
    signatures_adapter character varying(255) DEFAULT 'Elixir.Boruta.Internal.Signatures'::character varying NOT NULL,
    agent_token_ttl integer DEFAULT 2592000 NOT NULL,
    check_public_client_id boolean DEFAULT false NOT NULL
);


--
-- Name: oauth_scopes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oauth_scopes (
    id uuid NOT NULL,
    label character varying(255),
    name character varying(255) DEFAULT ''::character varying,
    public boolean DEFAULT false NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: oauth_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oauth_tokens (
    id uuid NOT NULL,
    type character varying(255),
    value text,
    refresh_token text,
    expires_at integer,
    redirect_uri character varying(255),
    state text,
    scope character varying(255) DEFAULT ''::character varying,
    revoked_at timestamp without time zone,
    code_challenge_hash character varying(255),
    code_challenge_method character varying(255),
    client_id uuid,
    sub text,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    nonce character varying(255),
    previous_token text,
    refresh_token_revoked_at timestamp without time zone,
    previous_code text,
    authorization_details jsonb DEFAULT '[]'::jsonb,
    c_nonce character varying(255),
    presentation_definition jsonb,
    tx_code character varying(255),
    bind_data jsonb,
    bind_configuration jsonb,
    agent_token character varying(255),
    public_client_id text
);


--
-- Name: oban_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oban_jobs (
    id bigint NOT NULL,
    state public.oban_job_state DEFAULT 'available'::public.oban_job_state NOT NULL,
    queue text DEFAULT 'default'::text NOT NULL,
    worker text NOT NULL,
    args jsonb DEFAULT '{}'::jsonb NOT NULL,
    errors jsonb[] DEFAULT ARRAY[]::jsonb[] NOT NULL,
    attempt integer DEFAULT 0 NOT NULL,
    max_attempts integer DEFAULT 20 NOT NULL,
    inserted_at timestamp without time zone DEFAULT timezone('UTC'::text, now()) NOT NULL,
    scheduled_at timestamp without time zone DEFAULT timezone('UTC'::text, now()) NOT NULL,
    attempted_at timestamp without time zone,
    completed_at timestamp without time zone,
    attempted_by text[],
    discarded_at timestamp without time zone,
    priority integer DEFAULT 0 NOT NULL,
    tags text[] DEFAULT ARRAY[]::text[],
    meta jsonb DEFAULT '{}'::jsonb,
    cancelled_at timestamp without time zone,
    CONSTRAINT attempt_range CHECK (((attempt >= 0) AND (attempt <= max_attempts))),
    CONSTRAINT positive_max_attempts CHECK ((max_attempts > 0)),
    CONSTRAINT queue_length CHECK (((char_length(queue) > 0) AND (char_length(queue) < 128))),
    CONSTRAINT worker_length CHECK (((char_length(worker) > 0) AND (char_length(worker) < 128)))
);


--
-- Name: TABLE oban_jobs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.oban_jobs IS '12';


--
-- Name: oban_jobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.oban_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: oban_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.oban_jobs_id_seq OWNED BY public.oban_jobs.id;


--
-- Name: oban_peers; Type: TABLE; Schema: public; Owner: -
--

CREATE UNLOGGED TABLE public.oban_peers (
    name text NOT NULL,
    node text NOT NULL,
    started_at timestamp without time zone NOT NULL,
    expires_at timestamp without time zone NOT NULL
);


--
-- Name: organizations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organizations (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    legacy boolean DEFAULT true NOT NULL,
    sso_provider integer,
    sso_organization_id character varying(255),
    okta_client_id character varying(255),
    okta_encrypted_client_secret bytea
);


--
-- Name: organizations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.organizations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: organizations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.organizations_id_seq OWNED BY public.organizations.id;


--
-- Name: package_download_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.package_download_events (
    id uuid NOT NULL,
    package_release_id uuid,
    account_id bigint NOT NULL,
    inserted_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: package_manifests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.package_manifests (
    id uuid NOT NULL,
    package_release_id uuid NOT NULL,
    swift_version character varying(255),
    swift_tools_version character varying(255),
    inserted_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: package_releases; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.package_releases (
    id uuid NOT NULL,
    package_id uuid NOT NULL,
    checksum character varying(255) NOT NULL,
    version character varying(255) NOT NULL,
    inserted_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: packages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.packages (
    id uuid NOT NULL,
    scope public.citext NOT NULL,
    name public.citext NOT NULL,
    last_updated_releases_at timestamp with time zone,
    inserted_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    repository_full_handle character varying(255)
);


--
-- Name: previews; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.previews (
    id uuid NOT NULL,
    project_id bigint NOT NULL,
    created_by_account_id bigint,
    display_name character varying(255),
    bundle_identifier character varying(255),
    version character varying(255),
    git_branch character varying(255),
    git_commit_sha character varying(255),
    git_ref character varying(255),
    supported_platforms integer[] DEFAULT ARRAY[]::integer[],
    visibility integer,
    inserted_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    track public.citext DEFAULT ''::public.citext NOT NULL
);


--
-- Name: project_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.project_tokens (
    id uuid NOT NULL,
    encrypted_token_hash character varying(255),
    project_id bigint,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: projects; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.projects (
    id bigint NOT NULL,
    name public.citext NOT NULL,
    token character varying(100) NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    account_id bigint NOT NULL,
    remote_cache_storage_type character varying,
    remote_cache_storage_id bigint,
    visibility integer DEFAULT 0 NOT NULL,
    default_branch character varying(255) DEFAULT 'main'::character varying NOT NULL,
    vcs_repository_full_handle character varying(255),
    vcs_provider integer,
    default_previews_visibility integer DEFAULT 0 NOT NULL,
    qa_app_description text DEFAULT ''::text NOT NULL,
    qa_email text DEFAULT ''::text NOT NULL,
    qa_password text DEFAULT ''::text NOT NULL,
    slack_channel_id character varying(255),
    slack_channel_name character varying(255),
    report_frequency integer DEFAULT 0 NOT NULL,
    report_days_of_week integer[] DEFAULT ARRAY[]::integer[] NOT NULL,
    report_schedule_time timestamp with time zone,
    report_timezone character varying(255),
    auto_quarantine_flaky_tests boolean DEFAULT true,
    flaky_test_alerts_enabled boolean DEFAULT false,
    flaky_test_alerts_slack_channel_id character varying(255),
    flaky_test_alerts_slack_channel_name character varying(255),
    auto_mark_flaky_tests boolean DEFAULT true,
    auto_mark_flaky_threshold integer DEFAULT 1,
    build_system integer DEFAULT 0 NOT NULL
);


--
-- Name: projects_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.projects_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: projects_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.projects_id_seq OWNED BY public.projects.id;


--
-- Name: qa_launch_argument_groups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.qa_launch_argument_groups (
    id uuid NOT NULL,
    project_id bigint NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    value text NOT NULL,
    inserted_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: qa_recordings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.qa_recordings (
    id uuid NOT NULL,
    qa_run_id uuid NOT NULL,
    started_at timestamp with time zone NOT NULL,
    duration integer NOT NULL,
    inserted_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: qa_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.qa_runs (
    id uuid NOT NULL,
    app_build_id uuid,
    prompt text NOT NULL,
    status character varying(255) DEFAULT 'pending'::character varying NOT NULL,
    inserted_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    vcs_repository_full_handle character varying(255),
    vcs_provider integer,
    git_ref character varying(255),
    issue_comment_id bigint,
    finished_at timestamp with time zone,
    launch_argument_groups jsonb DEFAULT '[]'::jsonb,
    app_description text DEFAULT ''::text NOT NULL,
    email text DEFAULT ''::text NOT NULL,
    password text DEFAULT ''::text NOT NULL
);


--
-- Name: qa_screenshots; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.qa_screenshots (
    id uuid NOT NULL,
    qa_run_id uuid NOT NULL,
    qa_step_id uuid,
    inserted_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: qa_steps; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.qa_steps (
    id uuid NOT NULL,
    qa_run_id uuid NOT NULL,
    action text NOT NULL,
    result text,
    issues text[] NOT NULL,
    inserted_at timestamp with time zone NOT NULL,
    started_at timestamp with time zone
);


--
-- Name: que_jobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.que_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: que_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.que_jobs_id_seq OWNED BY public.que_jobs.id;


--
-- Name: que_lockers; Type: TABLE; Schema: public; Owner: -
--

CREATE UNLOGGED TABLE public.que_lockers (
    pid integer NOT NULL,
    worker_count integer NOT NULL,
    worker_priorities integer[] NOT NULL,
    ruby_pid integer NOT NULL,
    ruby_hostname text NOT NULL,
    queues text[] NOT NULL,
    listening boolean NOT NULL,
    job_schema_version integer DEFAULT 1,
    CONSTRAINT valid_queues CHECK (((array_ndims(queues) = 1) AND (array_length(queues, 1) IS NOT NULL))),
    CONSTRAINT valid_worker_priorities CHECK (((array_ndims(worker_priorities) = 1) AND (array_length(worker_priorities, 1) IS NOT NULL)))
);


--
-- Name: que_scheduler_audit; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.que_scheduler_audit (
    scheduler_job_id bigint NOT NULL,
    executed_at timestamp with time zone NOT NULL
);


--
-- Name: TABLE que_scheduler_audit; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.que_scheduler_audit IS '7';


--
-- Name: que_scheduler_audit_enqueued; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.que_scheduler_audit_enqueued (
    scheduler_job_id bigint NOT NULL,
    job_class character varying(255) NOT NULL,
    queue character varying(255),
    priority integer,
    args jsonb NOT NULL,
    job_id bigint,
    run_at timestamp with time zone
);


--
-- Name: que_values; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.que_values (
    key text NOT NULL,
    value jsonb DEFAULT '{}'::jsonb NOT NULL,
    CONSTRAINT valid_value CHECK ((jsonb_typeof(value) = 'object'::text))
)
WITH (fillfactor='90');


--
-- Name: roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.roles (
    id bigint NOT NULL,
    name character varying,
    resource_type character varying,
    resource_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: roles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.roles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: roles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.roles_id_seq OWNED BY public.roles.id;


--
-- Name: s3_buckets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.s3_buckets (
    id bigint NOT NULL,
    name character varying NOT NULL,
    access_key_id character varying NOT NULL,
    secret_access_key character varying,
    iv character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    account_id bigint NOT NULL,
    region character varying NOT NULL
);


--
-- Name: s3_buckets_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.s3_buckets_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: s3_buckets_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.s3_buckets_id_seq OWNED BY public.s3_buckets.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version bigint NOT NULL,
    inserted_at timestamp without time zone
);


--
-- Name: slack_installations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.slack_installations (
    id uuid NOT NULL,
    account_id bigint NOT NULL,
    team_id character varying(255) NOT NULL,
    team_name character varying(255),
    access_token bytea NOT NULL,
    bot_user_id character varying(255),
    inserted_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: ssi_credentials; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ssi_credentials (
    id uuid NOT NULL,
    format character varying(255) NOT NULL,
    credential text NOT NULL,
    access_token character varying(255) NOT NULL,
    defered boolean NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: subscriptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.subscriptions (
    id bigint NOT NULL,
    subscription_id character varying(255),
    plan integer,
    status character varying(255),
    account_id bigint,
    default_payment_method character varying(255),
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    trial_end timestamp(0) without time zone
);


--
-- Name: subscriptions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.subscriptions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: subscriptions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.subscriptions_id_seq OWNED BY public.subscriptions.id;


--
-- Name: token_usages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.token_usages (
    id uuid NOT NULL,
    input_tokens integer NOT NULL,
    output_tokens integer NOT NULL,
    model character varying(255) NOT NULL,
    feature character varying(255) NOT NULL,
    feature_resource_id uuid NOT NULL,
    account_id bigint NOT NULL,
    "timestamp" timestamp with time zone NOT NULL,
    inserted_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id bigint NOT NULL,
    email public.citext DEFAULT ''::character varying NOT NULL,
    encrypted_password character varying DEFAULT ''::character varying NOT NULL,
    token character varying(100) NOT NULL,
    reset_password_token character varying,
    reset_password_sent_at timestamp without time zone,
    remember_created_at timestamp without time zone,
    sign_in_count integer DEFAULT 0 NOT NULL,
    current_sign_in_at timestamp without time zone,
    last_sign_in_at timestamp without time zone,
    current_sign_in_ip character varying,
    last_sign_in_ip character varying,
    confirmation_token character varying,
    confirmed_at timestamp without time zone,
    confirmation_sent_at timestamp without time zone,
    unconfirmed_email character varying,
    failed_attempts integer DEFAULT 0 NOT NULL,
    unlock_token character varying,
    locked_at timestamp without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    last_visited_project_id bigint
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: users_roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users_roles (
    user_id bigint,
    role_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: users_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users_tokens (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    token bytea NOT NULL,
    context character varying(255) NOT NULL,
    sent_to character varying(255),
    inserted_at timestamp(0) without time zone NOT NULL
);


--
-- Name: users_tokens_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_tokens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_tokens_id_seq OWNED BY public.users_tokens.id;


--
-- Name: vcs_connections; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vcs_connections (
    id uuid NOT NULL,
    project_id bigint NOT NULL,
    provider integer NOT NULL,
    repository_full_handle character varying(255) NOT NULL,
    created_by_id bigint,
    github_app_installation_id uuid NOT NULL,
    inserted_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: accounts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounts ALTER COLUMN id SET DEFAULT nextval('public.accounts_id_seq'::regclass);


--
-- Name: cache_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cache_events ALTER COLUMN id SET DEFAULT nextval('public.cache_events_id_seq'::regclass);


--
-- Name: command_events legacy_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.command_events ALTER COLUMN legacy_id SET DEFAULT nextval('public.command_events_id_seq'::regclass);


--
-- Name: device_codes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.device_codes ALTER COLUMN id SET DEFAULT nextval('public.device_codes_id_seq'::regclass);


--
-- Name: invitations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations ALTER COLUMN id SET DEFAULT nextval('public.invitations_id_seq'::regclass);


--
-- Name: oauth2_identities id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth2_identities ALTER COLUMN id SET DEFAULT nextval('public.oauth2_identities_id_seq'::regclass);


--
-- Name: oauth_clients_scopes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_clients_scopes ALTER COLUMN id SET DEFAULT nextval('public.clients_scopes_id_seq'::regclass);


--
-- Name: oban_jobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oban_jobs ALTER COLUMN id SET DEFAULT nextval('public.oban_jobs_id_seq'::regclass);


--
-- Name: organizations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations ALTER COLUMN id SET DEFAULT nextval('public.organizations_id_seq'::regclass);


--
-- Name: projects id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects ALTER COLUMN id SET DEFAULT nextval('public.projects_id_seq'::regclass);


--
-- Name: que_jobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.que_jobs ALTER COLUMN id SET DEFAULT nextval('public.que_jobs_id_seq'::regclass);


--
-- Name: roles id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles ALTER COLUMN id SET DEFAULT nextval('public.roles_id_seq'::regclass);


--
-- Name: s3_buckets id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.s3_buckets ALTER COLUMN id SET DEFAULT nextval('public.s3_buckets_id_seq'::regclass);


--
-- Name: subscriptions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions ALTER COLUMN id SET DEFAULT nextval('public.subscriptions_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: users_tokens id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users_tokens ALTER COLUMN id SET DEFAULT nextval('public.users_tokens_id_seq'::regclass);


--
-- Name: account_cache_endpoints account_cache_endpoints_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_cache_endpoints
    ADD CONSTRAINT account_cache_endpoints_pkey PRIMARY KEY (id);


--
-- Name: account_token_projects account_token_projects_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_token_projects
    ADD CONSTRAINT account_token_projects_pkey PRIMARY KEY (id);


--
-- Name: account_tokens account_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_tokens
    ADD CONSTRAINT account_tokens_pkey PRIMARY KEY (id);


--
-- Name: accounts accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT accounts_pkey PRIMARY KEY (id);


--
-- Name: alert_rules alert_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alert_rules
    ADD CONSTRAINT alert_rules_pkey PRIMARY KEY (id);


--
-- Name: alerts alerts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alerts
    ADD CONSTRAINT alerts_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: artifacts artifacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.artifacts
    ADD CONSTRAINT artifacts_pkey PRIMARY KEY (id);


--
-- Name: authorization_requests authorization_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.authorization_requests
    ADD CONSTRAINT authorization_requests_pkey PRIMARY KEY (id);


--
-- Name: build_runs build_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.build_runs
    ADD CONSTRAINT build_runs_pkey PRIMARY KEY (id, inserted_at);


--
-- Name: bundles bundles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bundles
    ADD CONSTRAINT bundles_pkey PRIMARY KEY (id);


--
-- Name: cache_action_items cache_action_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cache_action_items
    ADD CONSTRAINT cache_action_items_pkey PRIMARY KEY (id);


--
-- Name: cache_endpoints cache_endpoints_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cache_endpoints
    ADD CONSTRAINT cache_endpoints_pkey PRIMARY KEY (id);


--
-- Name: cache_events cache_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cache_events
    ADD CONSTRAINT cache_events_pkey PRIMARY KEY (id);


--
-- Name: oauth_clients clients_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_clients
    ADD CONSTRAINT clients_pkey PRIMARY KEY (id);


--
-- Name: oauth_clients_scopes clients_scopes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_clients_scopes
    ADD CONSTRAINT clients_scopes_pkey PRIMARY KEY (id);


--
-- Name: command_events command_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.command_events
    ADD CONSTRAINT command_events_pkey PRIMARY KEY (id, created_at);


--
-- Name: device_codes device_codes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.device_codes
    ADD CONSTRAINT device_codes_pkey PRIMARY KEY (id);


--
-- Name: feature_flags feature_flags_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.feature_flags
    ADD CONSTRAINT feature_flags_pkey PRIMARY KEY (id);


--
-- Name: github_app_installations github_app_installations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.github_app_installations
    ADD CONSTRAINT github_app_installations_pkey PRIMARY KEY (id);


--
-- Name: invitations invitations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT invitations_pkey PRIMARY KEY (id);


--
-- Name: oban_jobs non_negative_priority; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.oban_jobs
    ADD CONSTRAINT non_negative_priority CHECK ((priority >= 0)) NOT VALID;


--
-- Name: oauth2_identities oauth2_identities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth2_identities
    ADD CONSTRAINT oauth2_identities_pkey PRIMARY KEY (id);


--
-- Name: oban_jobs oban_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oban_jobs
    ADD CONSTRAINT oban_jobs_pkey PRIMARY KEY (id);


--
-- Name: oban_peers oban_peers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oban_peers
    ADD CONSTRAINT oban_peers_pkey PRIMARY KEY (name);


--
-- Name: organizations organizations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_pkey PRIMARY KEY (id);


--
-- Name: package_download_events package_download_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.package_download_events
    ADD CONSTRAINT package_download_events_pkey PRIMARY KEY (id);


--
-- Name: package_manifests package_manifests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.package_manifests
    ADD CONSTRAINT package_manifests_pkey PRIMARY KEY (id);


--
-- Name: package_releases package_releases_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.package_releases
    ADD CONSTRAINT package_releases_pkey PRIMARY KEY (id);


--
-- Name: packages packages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.packages
    ADD CONSTRAINT packages_pkey PRIMARY KEY (id);


--
-- Name: app_builds previews_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_builds
    ADD CONSTRAINT previews_pkey PRIMARY KEY (id);


--
-- Name: previews previews_pkey1; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.previews
    ADD CONSTRAINT previews_pkey1 PRIMARY KEY (id);


--
-- Name: project_tokens project_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_tokens
    ADD CONSTRAINT project_tokens_pkey PRIMARY KEY (id);


--
-- Name: projects projects_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT projects_pkey PRIMARY KEY (id);


--
-- Name: qa_launch_argument_groups qa_launch_argument_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.qa_launch_argument_groups
    ADD CONSTRAINT qa_launch_argument_groups_pkey PRIMARY KEY (id);


--
-- Name: qa_recordings qa_recordings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.qa_recordings
    ADD CONSTRAINT qa_recordings_pkey PRIMARY KEY (id);


--
-- Name: qa_runs qa_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.qa_runs
    ADD CONSTRAINT qa_runs_pkey PRIMARY KEY (id);


--
-- Name: qa_screenshots qa_screenshots_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.qa_screenshots
    ADD CONSTRAINT qa_screenshots_pkey PRIMARY KEY (id);


--
-- Name: qa_steps qa_steps_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.qa_steps
    ADD CONSTRAINT qa_steps_pkey PRIMARY KEY (id);


--
-- Name: que_jobs que_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.que_jobs
    ADD CONSTRAINT que_jobs_pkey PRIMARY KEY (id);


--
-- Name: que_lockers que_lockers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.que_lockers
    ADD CONSTRAINT que_lockers_pkey PRIMARY KEY (pid);


--
-- Name: que_scheduler_audit que_scheduler_audit_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.que_scheduler_audit
    ADD CONSTRAINT que_scheduler_audit_pkey PRIMARY KEY (scheduler_job_id);


--
-- Name: que_values que_values_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.que_values
    ADD CONSTRAINT que_values_pkey PRIMARY KEY (key);


--
-- Name: roles roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_pkey PRIMARY KEY (id);


--
-- Name: s3_buckets s3_buckets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.s3_buckets
    ADD CONSTRAINT s3_buckets_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: oauth_scopes scopes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_scopes
    ADD CONSTRAINT scopes_pkey PRIMARY KEY (id);


--
-- Name: slack_installations slack_installations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.slack_installations
    ADD CONSTRAINT slack_installations_pkey PRIMARY KEY (id);


--
-- Name: ssi_credentials ssi_credentials_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ssi_credentials
    ADD CONSTRAINT ssi_credentials_pkey PRIMARY KEY (id);


--
-- Name: subscriptions subscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT subscriptions_pkey PRIMARY KEY (id);


--
-- Name: token_usages token_usages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.token_usages
    ADD CONSTRAINT token_usages_pkey PRIMARY KEY (id);


--
-- Name: guardian_tokens tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.guardian_tokens
    ADD CONSTRAINT tokens_pkey PRIMARY KEY (jti, aud);


--
-- Name: oauth_tokens tokens_pkey1; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_tokens
    ADD CONSTRAINT tokens_pkey1 PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: users_tokens users_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users_tokens
    ADD CONSTRAINT users_tokens_pkey PRIMARY KEY (id);


--
-- Name: vcs_connections vcs_connections_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vcs_connections
    ADD CONSTRAINT vcs_connections_pkey PRIMARY KEY (id);


--
-- Name: account_cache_endpoints_account_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX account_cache_endpoints_account_id_index ON public.account_cache_endpoints USING btree (account_id);


--
-- Name: account_cache_endpoints_account_id_url_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX account_cache_endpoints_account_id_url_index ON public.account_cache_endpoints USING btree (account_id, url);


--
-- Name: account_token_projects_account_token_id_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX account_token_projects_account_token_id_project_id_index ON public.account_token_projects USING btree (account_token_id, project_id);


--
-- Name: account_token_projects_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX account_token_projects_project_id_index ON public.account_token_projects USING btree (project_id);


--
-- Name: account_tokens_account_id_encrypted_token_hash_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX account_tokens_account_id_encrypted_token_hash_index ON public.account_tokens USING btree (account_id, encrypted_token_hash);


--
-- Name: account_tokens_account_id_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX account_tokens_account_id_name_index ON public.account_tokens USING btree (account_id, name);


--
-- Name: accounts_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX accounts_name_index ON public.accounts USING btree (name);


--
-- Name: accounts_namespace_tenant_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX accounts_namespace_tenant_id_index ON public.accounts USING btree (namespace_tenant_id);


--
-- Name: accounts_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX accounts_organization_id_index ON public.accounts USING btree (organization_id);


--
-- Name: accounts_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX accounts_user_id_index ON public.accounts USING btree (user_id);


--
-- Name: alert_rules_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX alert_rules_project_id_index ON public.alert_rules USING btree (project_id);


--
-- Name: alerts_alert_rule_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX alerts_alert_rule_id_index ON public.alerts USING btree (alert_rule_id);


--
-- Name: alerts_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX alerts_inserted_at_index ON public.alerts USING btree (inserted_at);


--
-- Name: app_builds_binary_id_build_version_non_apk_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX app_builds_binary_id_build_version_non_apk_index ON public.app_builds USING btree (binary_id, build_version) WHERE (type <> 2);


--
-- Name: artifacts_artifact_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX artifacts_artifact_id_index ON public.artifacts USING btree (artifact_id);


--
-- Name: artifacts_bundle_id_artifact_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX artifacts_bundle_id_artifact_id_index ON public.artifacts USING btree (bundle_id, artifact_id);


--
-- Name: artifacts_bundle_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX artifacts_bundle_id_index ON public.artifacts USING btree (bundle_id);


--
-- Name: artifacts_bundle_id_top_level_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX artifacts_bundle_id_top_level_idx ON public.artifacts USING btree (bundle_id) WHERE (artifact_id IS NULL);


--
-- Name: build_runs_custom_tags_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX build_runs_custom_tags_index ON public.build_runs USING gin (custom_tags);


--
-- Name: build_runs_project_id_configuration_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX build_runs_project_id_configuration_inserted_at_index ON public.build_runs USING btree (project_id, configuration, inserted_at);


--
-- Name: build_runs_project_id_git_ref_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX build_runs_project_id_git_ref_inserted_at_index ON public.build_runs USING btree (project_id, git_ref, inserted_at);


--
-- Name: build_runs_project_id_scheme_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX build_runs_project_id_scheme_index ON public.build_runs USING btree (project_id, scheme);


--
-- Name: bundles_project_id_git_ref_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX bundles_project_id_git_ref_index ON public.bundles USING btree (project_id, git_ref);


--
-- Name: cache_action_items_hash_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX cache_action_items_hash_project_id_index ON public.cache_action_items USING btree (hash, project_id);


--
-- Name: cache_endpoints_url_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX cache_endpoints_url_index ON public.cache_endpoints USING btree (url);


--
-- Name: cache_events_hash_event_type_created_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX cache_events_hash_event_type_created_at_index ON public.cache_events USING btree (hash, event_type, created_at);


--
-- Name: cache_events_hash_event_type_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX cache_events_hash_event_type_index ON public.cache_events USING btree (hash, event_type);


--
-- Name: cache_events_project_id_created_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX cache_events_project_id_created_at_index ON public.cache_events USING btree (project_id, created_at);


--
-- Name: cache_events_project_id_event_type_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX cache_events_project_id_event_type_index ON public.cache_events USING btree (project_id, event_type);


--
-- Name: command_events_build_run_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX command_events_build_run_id_index ON public.command_events USING btree (build_run_id);


--
-- Name: command_events_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX command_events_id_index ON public.command_events USING btree (legacy_id);


--
-- Name: command_events_name_project_id_git_branch_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX command_events_name_project_id_git_branch_index ON public.command_events USING btree (name, project_id, git_branch);


--
-- Name: command_events_name_project_id_git_commit_sha_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX command_events_name_project_id_git_commit_sha_index ON public.command_events USING btree (name, project_id, git_commit_sha);


--
-- Name: command_events_name_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX command_events_name_project_id_index ON public.command_events USING btree (name, project_id);


--
-- Name: command_events_preview_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX command_events_preview_id_index ON public.command_events USING btree (preview_id);


--
-- Name: command_events_project_id_created_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX command_events_project_id_created_at_index ON public.command_events USING btree (project_id, created_at);


--
-- Name: command_events_remote_cache_target_hits_count_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX command_events_remote_cache_target_hits_count_index ON public.command_events USING btree (remote_cache_target_hits_count);


--
-- Name: command_events_remote_test_target_hits_count_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX command_events_remote_test_target_hits_count_index ON public.command_events USING btree (remote_test_target_hits_count);


--
-- Name: command_events_uuid_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX command_events_uuid_index ON public.command_events USING btree (id);


--
-- Name: fwf_flag_name_gate_target_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX fwf_flag_name_gate_target_idx ON public.feature_flags USING btree (flag_name, gate_type, target);


--
-- Name: github_app_installations_account_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX github_app_installations_account_id_index ON public.github_app_installations USING btree (account_id);


--
-- Name: github_app_installations_installation_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX github_app_installations_installation_id_index ON public.github_app_installations USING btree (installation_id);


--
-- Name: idx_on_provider_id_in_provider_user_id_1ddc3fbf56; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_provider_id_in_provider_user_id_1ddc3fbf56 ON public.oauth2_identities USING btree (provider, id_in_provider, user_id);


--
-- Name: index_accounts_on_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_accounts_on_customer_id ON public.accounts USING btree (customer_id);


--
-- Name: index_accounts_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_accounts_on_name ON public.accounts USING btree (name);


--
-- Name: index_cache_events_on_project_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cache_events_on_project_id ON public.cache_events USING btree (project_id);


--
-- Name: index_command_events_on_project_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_command_events_on_project_id ON public.command_events USING btree (project_id);


--
-- Name: index_device_codes_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_device_codes_on_user_id ON public.device_codes USING btree (user_id);


--
-- Name: index_invitations_on_inviter; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invitations_on_inviter ON public.invitations USING btree (inviter_type, inviter_id);


--
-- Name: index_invitations_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invitations_on_organization_id ON public.invitations USING btree (organization_id);


--
-- Name: index_invitations_on_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_invitations_on_token ON public.invitations USING btree (token);


--
-- Name: index_oauth2_identities_on_provider_and_id_in_provider; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_oauth2_identities_on_provider_and_id_in_provider ON public.oauth2_identities USING btree (provider, id_in_provider);


--
-- Name: index_oauth2_identities_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_oauth2_identities_on_user_id ON public.oauth2_identities USING btree (user_id);


--
-- Name: index_projects_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_projects_on_account_id ON public.projects USING btree (account_id);


--
-- Name: index_projects_on_name_and_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_projects_on_name_and_account_id ON public.projects USING btree (name, account_id);


--
-- Name: index_projects_on_remote_cache_storage; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_projects_on_remote_cache_storage ON public.projects USING btree (remote_cache_storage_type, remote_cache_storage_id);


--
-- Name: index_projects_on_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_projects_on_token ON public.projects USING btree (token);


--
-- Name: index_roles_on_name_and_resource_type_and_resource_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_roles_on_name_and_resource_type_and_resource_id ON public.roles USING btree (name, resource_type, resource_id);


--
-- Name: index_roles_on_resource; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_roles_on_resource ON public.roles USING btree (resource_type, resource_id);


--
-- Name: index_s3_buckets_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_s3_buckets_on_account_id ON public.s3_buckets USING btree (account_id);


--
-- Name: index_s3_buckets_on_name_and_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_s3_buckets_on_name_and_account_id ON public.s3_buckets USING btree (name, account_id);


--
-- Name: index_users_on_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_email ON public.users USING btree (email);


--
-- Name: index_users_on_last_visited_project_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_last_visited_project_id ON public.users USING btree (last_visited_project_id);


--
-- Name: index_users_on_reset_password_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_reset_password_token ON public.users USING btree (reset_password_token);


--
-- Name: index_users_on_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_token ON public.users USING btree (token);


--
-- Name: index_users_roles_on_role_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_roles_on_role_id ON public.users_roles USING btree (role_id);


--
-- Name: index_users_roles_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_roles_on_user_id ON public.users_roles USING btree (user_id);


--
-- Name: index_users_roles_on_user_id_and_role_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_roles_on_user_id_and_role_id ON public.users_roles USING btree (user_id, role_id);


--
-- Name: invitations_invitee_email_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX invitations_invitee_email_organization_id_index ON public.invitations USING btree (invitee_email, organization_id);


--
-- Name: oauth2_identities_user_id_provider_provider_organization_id_ind; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oauth2_identities_user_id_provider_provider_organization_id_ind ON public.oauth2_identities USING btree (user_id, provider, provider_organization_id);


--
-- Name: oauth_clients_id_secret_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX oauth_clients_id_secret_index ON public.oauth_clients USING btree (id, secret);


--
-- Name: oauth_scopes_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX oauth_scopes_name_index ON public.oauth_scopes USING btree (name);


--
-- Name: oauth_tokens_client_id_refresh_token_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX oauth_tokens_client_id_refresh_token_index ON public.oauth_tokens USING btree (client_id, refresh_token);


--
-- Name: oauth_tokens_client_id_value_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX oauth_tokens_client_id_value_index ON public.oauth_tokens USING btree (client_id, value);


--
-- Name: oauth_tokens_value_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oauth_tokens_value_index ON public.oauth_tokens USING btree (value);


--
-- Name: oban_jobs_args_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oban_jobs_args_index ON public.oban_jobs USING gin (args);


--
-- Name: oban_jobs_meta_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oban_jobs_meta_index ON public.oban_jobs USING gin (meta);


--
-- Name: oban_jobs_state_queue_priority_scheduled_at_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oban_jobs_state_queue_priority_scheduled_at_id_index ON public.oban_jobs USING btree (state, queue, priority, scheduled_at, id);


--
-- Name: organizations_sso_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX organizations_sso_organization_id_index ON public.organizations USING btree (sso_organization_id);


--
-- Name: organizations_sso_provider_sso_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX organizations_sso_provider_sso_organization_id_index ON public.organizations USING btree (sso_provider, sso_organization_id);


--
-- Name: package_download_events_account_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX package_download_events_account_id_index ON public.package_download_events USING btree (account_id);


--
-- Name: package_manifests_package_release_id_swift_version_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX package_manifests_package_release_id_swift_version_index ON public.package_manifests USING btree (package_release_id, swift_version);


--
-- Name: package_releases_package_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX package_releases_package_id_index ON public.package_releases USING btree (package_id);


--
-- Name: package_releases_package_id_version_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX package_releases_package_id_version_index ON public.package_releases USING btree (package_id, version);


--
-- Name: packages_scope_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX packages_scope_name_index ON public.packages USING btree (scope, name);


--
-- Name: previews_bundle_identifier_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX previews_bundle_identifier_index ON public.previews USING btree (bundle_identifier);


--
-- Name: previews_created_by_account_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX previews_created_by_account_id_index ON public.previews USING btree (created_by_account_id);


--
-- Name: previews_git_branch_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX previews_git_branch_index ON public.previews USING btree (git_branch);


--
-- Name: previews_git_commit_sha_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX previews_git_commit_sha_index ON public.previews USING btree (git_commit_sha);


--
-- Name: previews_project_id_git_ref_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX previews_project_id_git_ref_index ON public.previews USING btree (project_id, git_ref);


--
-- Name: previews_track_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX previews_track_index ON public.previews USING btree (track);


--
-- Name: project_tokens_encrypted_token_hash_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX project_tokens_encrypted_token_hash_index ON public.project_tokens USING btree (encrypted_token_hash);


--
-- Name: project_tokens_project_id_encrypted_token_hash_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX project_tokens_project_id_encrypted_token_hash_index ON public.project_tokens USING btree (project_id, encrypted_token_hash);


--
-- Name: qa_launch_argument_groups_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX qa_launch_argument_groups_name_index ON public.qa_launch_argument_groups USING btree (name);


--
-- Name: qa_launch_argument_groups_project_id_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX qa_launch_argument_groups_project_id_name_index ON public.qa_launch_argument_groups USING btree (project_id, name);


--
-- Name: qa_runs_app_build_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX qa_runs_app_build_id_index ON public.qa_runs USING btree (app_build_id);


--
-- Name: qa_runs_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX qa_runs_inserted_at_index ON public.qa_runs USING btree (inserted_at);


--
-- Name: qa_runs_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX qa_runs_status_index ON public.qa_runs USING btree (status);


--
-- Name: qa_runs_vcs_repository_full_handle_vcs_provider_git_ref_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX qa_runs_vcs_repository_full_handle_vcs_provider_git_ref_index ON public.qa_runs USING btree (vcs_repository_full_handle, vcs_provider, git_ref);


--
-- Name: qa_screenshots_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX qa_screenshots_inserted_at_index ON public.qa_screenshots USING btree (inserted_at);


--
-- Name: qa_screenshots_qa_run_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX qa_screenshots_qa_run_id_index ON public.qa_screenshots USING btree (qa_run_id);


--
-- Name: qa_screenshots_qa_step_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX qa_screenshots_qa_step_id_index ON public.qa_screenshots USING btree (qa_step_id);


--
-- Name: qa_steps_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX qa_steps_inserted_at_index ON public.qa_steps USING btree (inserted_at);


--
-- Name: qa_steps_qa_run_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX qa_steps_qa_run_id_index ON public.qa_steps USING btree (qa_run_id);


--
-- Name: que_jobs_args_gin_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX que_jobs_args_gin_idx ON public.que_jobs USING gin (args jsonb_path_ops);


--
-- Name: que_jobs_data_gin_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX que_jobs_data_gin_idx ON public.que_jobs USING gin (data jsonb_path_ops);


--
-- Name: que_jobs_kwargs_gin_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX que_jobs_kwargs_gin_idx ON public.que_jobs USING gin (kwargs jsonb_path_ops);


--
-- Name: que_poll_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX que_poll_idx ON public.que_jobs USING btree (job_schema_version, queue, priority, run_at, id) WHERE ((finished_at IS NULL) AND (expired_at IS NULL));


--
-- Name: que_scheduler_audit_enqueued_args; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX que_scheduler_audit_enqueued_args ON public.que_scheduler_audit_enqueued USING btree (args);


--
-- Name: que_scheduler_audit_enqueued_job_class; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX que_scheduler_audit_enqueued_job_class ON public.que_scheduler_audit_enqueued USING btree (job_class);


--
-- Name: que_scheduler_audit_enqueued_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX que_scheduler_audit_enqueued_job_id ON public.que_scheduler_audit_enqueued USING btree (job_id);


--
-- Name: que_scheduler_job_in_que_jobs_unique_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX que_scheduler_job_in_que_jobs_unique_index ON public.que_jobs USING btree (job_class) WHERE (job_class = 'Que::Scheduler::SchedulerJob'::text);


--
-- Name: slack_installations_account_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX slack_installations_account_id_index ON public.slack_installations USING btree (account_id);


--
-- Name: slack_installations_team_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX slack_installations_team_id_index ON public.slack_installations USING btree (team_id);


--
-- Name: subscriptions_account_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX subscriptions_account_id_index ON public.subscriptions USING btree (account_id);


--
-- Name: subscriptions_account_id_status_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX subscriptions_account_id_status_inserted_at_index ON public.subscriptions USING btree (account_id, status, inserted_at);


--
-- Name: subscriptions_subscription_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX subscriptions_subscription_id_index ON public.subscriptions USING btree (subscription_id);


--
-- Name: token_usages_account_feature_timestamp_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX token_usages_account_feature_timestamp_idx ON public.token_usages USING btree (account_id, feature, "timestamp" DESC);


--
-- Name: token_usages_account_id_timestamp_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX token_usages_account_id_timestamp_index ON public.token_usages USING btree (account_id, "timestamp");


--
-- Name: token_usages_feature_resource_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX token_usages_feature_resource_id_index ON public.token_usages USING btree (feature_resource_id);


--
-- Name: token_usages_timestamp_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX token_usages_timestamp_index ON public.token_usages USING btree ("timestamp");


--
-- Name: users_roles_role_id_unique_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX users_roles_role_id_unique_index ON public.users_roles USING btree (role_id);


--
-- Name: users_tokens_context_token_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX users_tokens_context_token_index ON public.users_tokens USING btree (context, token);


--
-- Name: users_tokens_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX users_tokens_user_id_index ON public.users_tokens USING btree (user_id);


--
-- Name: vcs_connections_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX vcs_connections_project_id_index ON public.vcs_connections USING btree (project_id);


--
-- Name: vcs_connections_repository_full_handle_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vcs_connections_repository_full_handle_index ON public.vcs_connections USING btree (repository_full_handle);


--
-- Name: que_jobs que_job_notify; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER que_job_notify AFTER INSERT ON public.que_jobs FOR EACH ROW WHEN ((NOT (COALESCE(current_setting('que.skip_notify'::text, true), ''::text) = 'true'::text))) EXECUTE FUNCTION public.que_job_notify();


--
-- Name: que_jobs que_scheduler_prevent_job_deletion_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER que_scheduler_prevent_job_deletion_trigger AFTER DELETE OR UPDATE ON public.que_jobs DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.que_scheduler_prevent_job_deletion();


--
-- Name: que_jobs que_state_notify; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER que_state_notify AFTER INSERT OR DELETE OR UPDATE ON public.que_jobs FOR EACH ROW WHEN ((NOT (COALESCE(current_setting('que.skip_notify'::text, true), ''::text) = 'true'::text))) EXECUTE FUNCTION public.que_state_notify();


--
-- Name: account_cache_endpoints account_cache_endpoints_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_cache_endpoints
    ADD CONSTRAINT account_cache_endpoints_account_id_fkey FOREIGN KEY (account_id) REFERENCES public.accounts(id) ON DELETE CASCADE;


--
-- Name: account_token_projects account_token_projects_account_token_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_token_projects
    ADD CONSTRAINT account_token_projects_account_token_id_fkey FOREIGN KEY (account_token_id) REFERENCES public.account_tokens(id) ON DELETE CASCADE;


--
-- Name: account_token_projects account_token_projects_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_token_projects
    ADD CONSTRAINT account_token_projects_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE;


--
-- Name: account_tokens account_tokens_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_tokens
    ADD CONSTRAINT account_tokens_account_id_fkey FOREIGN KEY (account_id) REFERENCES public.accounts(id) ON DELETE CASCADE;


--
-- Name: account_tokens account_tokens_created_by_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_tokens
    ADD CONSTRAINT account_tokens_created_by_account_id_fkey FOREIGN KEY (created_by_account_id) REFERENCES public.accounts(id) ON DELETE SET NULL;


--
-- Name: accounts accounts_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT accounts_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: accounts accounts_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT accounts_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: alert_rules alert_rules_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alert_rules
    ADD CONSTRAINT alert_rules_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE;


--
-- Name: alerts alerts_alert_rule_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alerts
    ADD CONSTRAINT alerts_alert_rule_id_fkey FOREIGN KEY (alert_rule_id) REFERENCES public.alert_rules(id) ON DELETE CASCADE;


--
-- Name: app_builds app_builds_preview_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_builds
    ADD CONSTRAINT app_builds_preview_id_fkey FOREIGN KEY (preview_id) REFERENCES public.previews(id) ON DELETE CASCADE;


--
-- Name: artifacts artifacts_bundle_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.artifacts
    ADD CONSTRAINT artifacts_bundle_id_fkey FOREIGN KEY (bundle_id) REFERENCES public.bundles(id) ON DELETE CASCADE;


--
-- Name: build_runs build_runs_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.build_runs
    ADD CONSTRAINT build_runs_account_id_fkey FOREIGN KEY (account_id) REFERENCES public.accounts(id) ON DELETE CASCADE;


--
-- Name: build_runs build_runs_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.build_runs
    ADD CONSTRAINT build_runs_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE;


--
-- Name: bundles bundles_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bundles
    ADD CONSTRAINT bundles_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE;


--
-- Name: bundles bundles_uploaded_by_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bundles
    ADD CONSTRAINT bundles_uploaded_by_account_id_fkey FOREIGN KEY (uploaded_by_account_id) REFERENCES public.accounts(id) ON DELETE SET NULL;


--
-- Name: device_codes device_codes_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.device_codes
    ADD CONSTRAINT device_codes_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: s3_buckets fk_rails_9f283692d5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.s3_buckets
    ADD CONSTRAINT fk_rails_9f283692d5 FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: github_app_installations github_app_installations_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.github_app_installations
    ADD CONSTRAINT github_app_installations_account_id_fkey FOREIGN KEY (account_id) REFERENCES public.accounts(id) ON DELETE CASCADE;


--
-- Name: invitations invitations_inviter_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT invitations_inviter_id_fkey FOREIGN KEY (inviter_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: invitations invitations_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT invitations_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: oauth_clients_scopes oauth_clients_scopes_client_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_clients_scopes
    ADD CONSTRAINT oauth_clients_scopes_client_id_fkey FOREIGN KEY (client_id) REFERENCES public.oauth_clients(id) ON DELETE CASCADE;


--
-- Name: oauth_clients_scopes oauth_clients_scopes_scope_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_clients_scopes
    ADD CONSTRAINT oauth_clients_scopes_scope_id_fkey FOREIGN KEY (scope_id) REFERENCES public.oauth_scopes(id) ON DELETE CASCADE;


--
-- Name: package_download_events package_download_events_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.package_download_events
    ADD CONSTRAINT package_download_events_account_id_fkey FOREIGN KEY (account_id) REFERENCES public.accounts(id) ON DELETE CASCADE;


--
-- Name: package_download_events package_download_events_package_release_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.package_download_events
    ADD CONSTRAINT package_download_events_package_release_id_fkey FOREIGN KEY (package_release_id) REFERENCES public.package_releases(id) ON DELETE SET NULL;


--
-- Name: package_manifests package_manifests_package_release_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.package_manifests
    ADD CONSTRAINT package_manifests_package_release_id_fkey FOREIGN KEY (package_release_id) REFERENCES public.package_releases(id) ON DELETE CASCADE;


--
-- Name: package_releases package_releases_package_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.package_releases
    ADD CONSTRAINT package_releases_package_id_fkey FOREIGN KEY (package_id) REFERENCES public.packages(id) ON DELETE CASCADE;


--
-- Name: previews previews_created_by_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.previews
    ADD CONSTRAINT previews_created_by_account_id_fkey FOREIGN KEY (created_by_account_id) REFERENCES public.accounts(id) ON DELETE CASCADE;


--
-- Name: previews previews_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.previews
    ADD CONSTRAINT previews_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE;


--
-- Name: project_tokens project_tokens_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_tokens
    ADD CONSTRAINT project_tokens_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE;


--
-- Name: projects projects_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT projects_account_id_fkey FOREIGN KEY (account_id) REFERENCES public.accounts(id) ON DELETE CASCADE;


--
-- Name: qa_launch_argument_groups qa_launch_argument_groups_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.qa_launch_argument_groups
    ADD CONSTRAINT qa_launch_argument_groups_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE;


--
-- Name: qa_recordings qa_recordings_qa_run_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.qa_recordings
    ADD CONSTRAINT qa_recordings_qa_run_id_fkey FOREIGN KEY (qa_run_id) REFERENCES public.qa_runs(id) ON DELETE CASCADE;


--
-- Name: qa_runs qa_runs_app_build_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.qa_runs
    ADD CONSTRAINT qa_runs_app_build_id_fkey FOREIGN KEY (app_build_id) REFERENCES public.app_builds(id) ON DELETE CASCADE;


--
-- Name: qa_screenshots qa_screenshots_qa_run_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.qa_screenshots
    ADD CONSTRAINT qa_screenshots_qa_run_id_fkey FOREIGN KEY (qa_run_id) REFERENCES public.qa_runs(id) ON DELETE CASCADE;


--
-- Name: qa_screenshots qa_screenshots_qa_step_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.qa_screenshots
    ADD CONSTRAINT qa_screenshots_qa_step_id_fkey FOREIGN KEY (qa_step_id) REFERENCES public.qa_steps(id) ON DELETE CASCADE;


--
-- Name: qa_steps qa_steps_qa_run_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.qa_steps
    ADD CONSTRAINT qa_steps_qa_run_id_fkey FOREIGN KEY (qa_run_id) REFERENCES public.qa_runs(id) ON DELETE CASCADE;


--
-- Name: que_scheduler_audit_enqueued que_scheduler_audit_enqueued_scheduler_job_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.que_scheduler_audit_enqueued
    ADD CONSTRAINT que_scheduler_audit_enqueued_scheduler_job_id_fkey FOREIGN KEY (scheduler_job_id) REFERENCES public.que_scheduler_audit(scheduler_job_id);


--
-- Name: slack_installations slack_installations_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.slack_installations
    ADD CONSTRAINT slack_installations_account_id_fkey FOREIGN KEY (account_id) REFERENCES public.accounts(id) ON DELETE CASCADE;


--
-- Name: subscriptions subscriptions_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT subscriptions_account_id_fkey FOREIGN KEY (account_id) REFERENCES public.accounts(id) ON DELETE CASCADE;


--
-- Name: token_usages token_usages_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.token_usages
    ADD CONSTRAINT token_usages_account_id_fkey FOREIGN KEY (account_id) REFERENCES public.accounts(id) ON DELETE CASCADE;


--
-- Name: users users_last_visited_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_last_visited_project_id_fkey FOREIGN KEY (last_visited_project_id) REFERENCES public.projects(id) ON DELETE SET NULL;


--
-- Name: users_tokens users_tokens_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users_tokens
    ADD CONSTRAINT users_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: vcs_connections vcs_connections_created_by_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vcs_connections
    ADD CONSTRAINT vcs_connections_created_by_id_fkey FOREIGN KEY (created_by_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: vcs_connections vcs_connections_github_app_installation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vcs_connections
    ADD CONSTRAINT vcs_connections_github_app_installation_id_fkey FOREIGN KEY (github_app_installation_id) REFERENCES public.github_app_installations(id) ON DELETE CASCADE;


--
-- Name: vcs_connections vcs_connections_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vcs_connections
    ADD CONSTRAINT vcs_connections_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

INSERT INTO public."schema_migrations" (version) VALUES (20240330135148);
INSERT INTO public."schema_migrations" (version) VALUES (20240415140351);
INSERT INTO public."schema_migrations" (version) VALUES (20240502145712);
INSERT INTO public."schema_migrations" (version) VALUES (20240504124210);
INSERT INTO public."schema_migrations" (version) VALUES (20240507140636);
INSERT INTO public."schema_migrations" (version) VALUES (20240510215420);
INSERT INTO public."schema_migrations" (version) VALUES (20240512093328);
INSERT INTO public."schema_migrations" (version) VALUES (20240512202735);
INSERT INTO public."schema_migrations" (version) VALUES (20240513131757);
INSERT INTO public."schema_migrations" (version) VALUES (20240514104516);
INSERT INTO public."schema_migrations" (version) VALUES (20240516083924);
INSERT INTO public."schema_migrations" (version) VALUES (20240517130605);
INSERT INTO public."schema_migrations" (version) VALUES (20240517133831);
INSERT INTO public."schema_migrations" (version) VALUES (20240517160646);
INSERT INTO public."schema_migrations" (version) VALUES (20240520133751);
INSERT INTO public."schema_migrations" (version) VALUES (20240520161436);
INSERT INTO public."schema_migrations" (version) VALUES (20240521153013);
INSERT INTO public."schema_migrations" (version) VALUES (20240521153130);
INSERT INTO public."schema_migrations" (version) VALUES (20240522073355);
INSERT INTO public."schema_migrations" (version) VALUES (20240522084312);
INSERT INTO public."schema_migrations" (version) VALUES (20240522140434);
INSERT INTO public."schema_migrations" (version) VALUES (20240606140822);
INSERT INTO public."schema_migrations" (version) VALUES (20240611104446);
INSERT INTO public."schema_migrations" (version) VALUES (20240618085059);
INSERT INTO public."schema_migrations" (version) VALUES (20240618153206);
INSERT INTO public."schema_migrations" (version) VALUES (20240624072132);
INSERT INTO public."schema_migrations" (version) VALUES (20240701140010);
INSERT INTO public."schema_migrations" (version) VALUES (20240701145826);
INSERT INTO public."schema_migrations" (version) VALUES (20240709132024);
INSERT INTO public."schema_migrations" (version) VALUES (20240710084015);
INSERT INTO public."schema_migrations" (version) VALUES (20240717161941);
INSERT INTO public."schema_migrations" (version) VALUES (20240717162102);
INSERT INTO public."schema_migrations" (version) VALUES (20240717162208);
INSERT INTO public."schema_migrations" (version) VALUES (20240717162430);
INSERT INTO public."schema_migrations" (version) VALUES (20240717162512);
INSERT INTO public."schema_migrations" (version) VALUES (20240717162537);
INSERT INTO public."schema_migrations" (version) VALUES (20240722130022);
INSERT INTO public."schema_migrations" (version) VALUES (20240722153521);
INSERT INTO public."schema_migrations" (version) VALUES (20240722155421);
INSERT INTO public."schema_migrations" (version) VALUES (20240722163519);
INSERT INTO public."schema_migrations" (version) VALUES (20240722170258);
INSERT INTO public."schema_migrations" (version) VALUES (20240724152442);
INSERT INTO public."schema_migrations" (version) VALUES (20240730155615);
INSERT INTO public."schema_migrations" (version) VALUES (20240802081942);
INSERT INTO public."schema_migrations" (version) VALUES (20240802100720);
INSERT INTO public."schema_migrations" (version) VALUES (20240807084244);
INSERT INTO public."schema_migrations" (version) VALUES (20240812154446);
INSERT INTO public."schema_migrations" (version) VALUES (20240812160349);
INSERT INTO public."schema_migrations" (version) VALUES (20240812160436);
INSERT INTO public."schema_migrations" (version) VALUES (20240812160729);
INSERT INTO public."schema_migrations" (version) VALUES (20240812160942);
INSERT INTO public."schema_migrations" (version) VALUES (20240812161023);
INSERT INTO public."schema_migrations" (version) VALUES (20240823080441);
INSERT INTO public."schema_migrations" (version) VALUES (20240823082825);
INSERT INTO public."schema_migrations" (version) VALUES (20240823102412);
INSERT INTO public."schema_migrations" (version) VALUES (20240826072642);
INSERT INTO public."schema_migrations" (version) VALUES (20240827134401);
INSERT INTO public."schema_migrations" (version) VALUES (20240830092226);
INSERT INTO public."schema_migrations" (version) VALUES (20240830092409);
INSERT INTO public."schema_migrations" (version) VALUES (20240830092638);
INSERT INTO public."schema_migrations" (version) VALUES (20240830093320);
INSERT INTO public."schema_migrations" (version) VALUES (20240904144057);
INSERT INTO public."schema_migrations" (version) VALUES (20240905090349);
INSERT INTO public."schema_migrations" (version) VALUES (20241009133121);
INSERT INTO public."schema_migrations" (version) VALUES (20241017144227);
INSERT INTO public."schema_migrations" (version) VALUES (20241104180504);
INSERT INTO public."schema_migrations" (version) VALUES (20241105165836);
INSERT INTO public."schema_migrations" (version) VALUES (20241105170106);
INSERT INTO public."schema_migrations" (version) VALUES (20241112115859);
INSERT INTO public."schema_migrations" (version) VALUES (20241113101458);
INSERT INTO public."schema_migrations" (version) VALUES (20241115113306);
INSERT INTO public."schema_migrations" (version) VALUES (20241115113353);
INSERT INTO public."schema_migrations" (version) VALUES (20241115113529);
INSERT INTO public."schema_migrations" (version) VALUES (20241119161847);
INSERT INTO public."schema_migrations" (version) VALUES (20241119161955);
INSERT INTO public."schema_migrations" (version) VALUES (20241119162139);
INSERT INTO public."schema_migrations" (version) VALUES (20241119163921);
INSERT INTO public."schema_migrations" (version) VALUES (20241120094604);
INSERT INTO public."schema_migrations" (version) VALUES (20241120095216);
INSERT INTO public."schema_migrations" (version) VALUES (20241202170656);
INSERT INTO public."schema_migrations" (version) VALUES (20241202170670);
INSERT INTO public."schema_migrations" (version) VALUES (20241205132128);
INSERT INTO public."schema_migrations" (version) VALUES (20241209165131);
INSERT INTO public."schema_migrations" (version) VALUES (20241224093643);
INSERT INTO public."schema_migrations" (version) VALUES (20250106161642);
INSERT INTO public."schema_migrations" (version) VALUES (20250109102003);
INSERT INTO public."schema_migrations" (version) VALUES (20250123094833);
INSERT INTO public."schema_migrations" (version) VALUES (20250123095128);
INSERT INTO public."schema_migrations" (version) VALUES (20250123095200);
INSERT INTO public."schema_migrations" (version) VALUES (20250124145216);
INSERT INTO public."schema_migrations" (version) VALUES (20250128153554);
INSERT INTO public."schema_migrations" (version) VALUES (20250130181711);
INSERT INTO public."schema_migrations" (version) VALUES (20250224154433);
INSERT INTO public."schema_migrations" (version) VALUES (20250227103037);
INSERT INTO public."schema_migrations" (version) VALUES (20250228160232);
INSERT INTO public."schema_migrations" (version) VALUES (20250306144609);
INSERT INTO public."schema_migrations" (version) VALUES (20250320095026);
INSERT INTO public."schema_migrations" (version) VALUES (20250401080050);
INSERT INTO public."schema_migrations" (version) VALUES (20250401080111);
INSERT INTO public."schema_migrations" (version) VALUES (20250401081625);
INSERT INTO public."schema_migrations" (version) VALUES (20250401142536);
INSERT INTO public."schema_migrations" (version) VALUES (20250401142743);
INSERT INTO public."schema_migrations" (version) VALUES (20250402115006);
INSERT INTO public."schema_migrations" (version) VALUES (20250408090938);
INSERT INTO public."schema_migrations" (version) VALUES (20250408104000);
INSERT INTO public."schema_migrations" (version) VALUES (20250408122442);
INSERT INTO public."schema_migrations" (version) VALUES (20250417162027);
INSERT INTO public."schema_migrations" (version) VALUES (20250422091839);
INSERT INTO public."schema_migrations" (version) VALUES (20250422162510);
INSERT INTO public."schema_migrations" (version) VALUES (20250423102826);
INSERT INTO public."schema_migrations" (version) VALUES (20250516130921);
INSERT INTO public."schema_migrations" (version) VALUES (20250516164931);
INSERT INTO public."schema_migrations" (version) VALUES (20250523150018);
INSERT INTO public."schema_migrations" (version) VALUES (20250526090224);
INSERT INTO public."schema_migrations" (version) VALUES (20250527141430);
INSERT INTO public."schema_migrations" (version) VALUES (20250528140917);
INSERT INTO public."schema_migrations" (version) VALUES (20250609115515);
INSERT INTO public."schema_migrations" (version) VALUES (20250611093946);
INSERT INTO public."schema_migrations" (version) VALUES (20250611095739);
INSERT INTO public."schema_migrations" (version) VALUES (20250611171448);
INSERT INTO public."schema_migrations" (version) VALUES (20250611171830);
INSERT INTO public."schema_migrations" (version) VALUES (20250612115646);
INSERT INTO public."schema_migrations" (version) VALUES (20250613140005);
INSERT INTO public."schema_migrations" (version) VALUES (20250613144635);
INSERT INTO public."schema_migrations" (version) VALUES (20250615093614);
INSERT INTO public."schema_migrations" (version) VALUES (20250615110403);
INSERT INTO public."schema_migrations" (version) VALUES (20250615121456);
INSERT INTO public."schema_migrations" (version) VALUES (20250616123552);
INSERT INTO public."schema_migrations" (version) VALUES (20250616124414);
INSERT INTO public."schema_migrations" (version) VALUES (20250618094058);
INSERT INTO public."schema_migrations" (version) VALUES (20250619102929);
INSERT INTO public."schema_migrations" (version) VALUES (20250619103147);
INSERT INTO public."schema_migrations" (version) VALUES (20250620042537);
INSERT INTO public."schema_migrations" (version) VALUES (20250623090458);
INSERT INTO public."schema_migrations" (version) VALUES (20250623091734);
INSERT INTO public."schema_migrations" (version) VALUES (20250623091735);
INSERT INTO public."schema_migrations" (version) VALUES (20250623091736);
INSERT INTO public."schema_migrations" (version) VALUES (20250623091737);
INSERT INTO public."schema_migrations" (version) VALUES (20250623091738);
INSERT INTO public."schema_migrations" (version) VALUES (20250623091739);
INSERT INTO public."schema_migrations" (version) VALUES (20250623091740);
INSERT INTO public."schema_migrations" (version) VALUES (20250623091741);
INSERT INTO public."schema_migrations" (version) VALUES (20250623091742);
INSERT INTO public."schema_migrations" (version) VALUES (20250623091743);
INSERT INTO public."schema_migrations" (version) VALUES (20250623091744);
INSERT INTO public."schema_migrations" (version) VALUES (20250623091745);
INSERT INTO public."schema_migrations" (version) VALUES (20250623091746);
INSERT INTO public."schema_migrations" (version) VALUES (20250623091747);
INSERT INTO public."schema_migrations" (version) VALUES (20250623091748);
INSERT INTO public."schema_migrations" (version) VALUES (20250623091749);
INSERT INTO public."schema_migrations" (version) VALUES (20250623091750);
INSERT INTO public."schema_migrations" (version) VALUES (20250623091751);
INSERT INTO public."schema_migrations" (version) VALUES (20250623091752);
INSERT INTO public."schema_migrations" (version) VALUES (20250623091753);
INSERT INTO public."schema_migrations" (version) VALUES (20250623091754);
INSERT INTO public."schema_migrations" (version) VALUES (20250623091755);
INSERT INTO public."schema_migrations" (version) VALUES (20250623091756);
INSERT INTO public."schema_migrations" (version) VALUES (20250623091757);
INSERT INTO public."schema_migrations" (version) VALUES (20250623091758);
INSERT INTO public."schema_migrations" (version) VALUES (20250623091759);
INSERT INTO public."schema_migrations" (version) VALUES (20250623091800);
INSERT INTO public."schema_migrations" (version) VALUES (20250623091801);
INSERT INTO public."schema_migrations" (version) VALUES (20250623091802);
INSERT INTO public."schema_migrations" (version) VALUES (20250623091803);
INSERT INTO public."schema_migrations" (version) VALUES (20250623163352);
INSERT INTO public."schema_migrations" (version) VALUES (20250625085629);
INSERT INTO public."schema_migrations" (version) VALUES (20250625090000);
INSERT INTO public."schema_migrations" (version) VALUES (20250703104053);
INSERT INTO public."schema_migrations" (version) VALUES (20250721130110);
INSERT INTO public."schema_migrations" (version) VALUES (20250730154655);
INSERT INTO public."schema_migrations" (version) VALUES (20250731162845);
INSERT INTO public."schema_migrations" (version) VALUES (20250805121532);
INSERT INTO public."schema_migrations" (version) VALUES (20250805121921);
INSERT INTO public."schema_migrations" (version) VALUES (20250805130346);
INSERT INTO public."schema_migrations" (version) VALUES (20250807133557);
INSERT INTO public."schema_migrations" (version) VALUES (20250807133739);
INSERT INTO public."schema_migrations" (version) VALUES (20250807144032);
INSERT INTO public."schema_migrations" (version) VALUES (20250811121337);
INSERT INTO public."schema_migrations" (version) VALUES (20250813084853);
INSERT INTO public."schema_migrations" (version) VALUES (20250815134927);
INSERT INTO public."schema_migrations" (version) VALUES (20250818104313);
INSERT INTO public."schema_migrations" (version) VALUES (20250818105845);
INSERT INTO public."schema_migrations" (version) VALUES (20250818131516);
INSERT INTO public."schema_migrations" (version) VALUES (20250818155249);
INSERT INTO public."schema_migrations" (version) VALUES (20250821093804);
INSERT INTO public."schema_migrations" (version) VALUES (20250826000001);
INSERT INTO public."schema_migrations" (version) VALUES (20250828065245);
INSERT INTO public."schema_migrations" (version) VALUES (20250901113436);
INSERT INTO public."schema_migrations" (version) VALUES (20250908174618);
INSERT INTO public."schema_migrations" (version) VALUES (20250909124838);
INSERT INTO public."schema_migrations" (version) VALUES (20250910084708);
INSERT INTO public."schema_migrations" (version) VALUES (20250910095538);
INSERT INTO public."schema_migrations" (version) VALUES (20250911090305);
INSERT INTO public."schema_migrations" (version) VALUES (20250911092114);
INSERT INTO public."schema_migrations" (version) VALUES (20250911123301);
INSERT INTO public."schema_migrations" (version) VALUES (20250915145208);
INSERT INTO public."schema_migrations" (version) VALUES (20250916075933);
INSERT INTO public."schema_migrations" (version) VALUES (20250916143744);
INSERT INTO public."schema_migrations" (version) VALUES (20250917084738);
INSERT INTO public."schema_migrations" (version) VALUES (20250917084814);
INSERT INTO public."schema_migrations" (version) VALUES (20250919153646);
INSERT INTO public."schema_migrations" (version) VALUES (20250929085828);
INSERT INTO public."schema_migrations" (version) VALUES (20250929150123);
INSERT INTO public."schema_migrations" (version) VALUES (20250929183241);
INSERT INTO public."schema_migrations" (version) VALUES (20250930122349);
INSERT INTO public."schema_migrations" (version) VALUES (20251002081758);
INSERT INTO public."schema_migrations" (version) VALUES (20251002133935);
INSERT INTO public."schema_migrations" (version) VALUES (20251002135728);
INSERT INTO public."schema_migrations" (version) VALUES (20251007163738);
INSERT INTO public."schema_migrations" (version) VALUES (20251028151803);
INSERT INTO public."schema_migrations" (version) VALUES (20251030214703);
INSERT INTO public."schema_migrations" (version) VALUES (20251125075727);
INSERT INTO public."schema_migrations" (version) VALUES (20251125165255);
INSERT INTO public."schema_migrations" (version) VALUES (20251125165658);
INSERT INTO public."schema_migrations" (version) VALUES (20251125173221);
INSERT INTO public."schema_migrations" (version) VALUES (20251127151517);
INSERT INTO public."schema_migrations" (version) VALUES (20251204190540);
INSERT INTO public."schema_migrations" (version) VALUES (20251204190541);
INSERT INTO public."schema_migrations" (version) VALUES (20251205101546);
INSERT INTO public."schema_migrations" (version) VALUES (20251212123658);
INSERT INTO public."schema_migrations" (version) VALUES (20251216150949);
INSERT INTO public."schema_migrations" (version) VALUES (20251216165255);
INSERT INTO public."schema_migrations" (version) VALUES (20251221191102);
INSERT INTO public."schema_migrations" (version) VALUES (20251222160354);
INSERT INTO public."schema_migrations" (version) VALUES (20251222170523);
INSERT INTO public."schema_migrations" (version) VALUES (20251230104056);
INSERT INTO public."schema_migrations" (version) VALUES (20260105151656);
INSERT INTO public."schema_migrations" (version) VALUES (20260107145239);
INSERT INTO public."schema_migrations" (version) VALUES (20260112130205);
INSERT INTO public."schema_migrations" (version) VALUES (20260115183645);
INSERT INTO public."schema_migrations" (version) VALUES (20260115200000);
INSERT INTO public."schema_migrations" (version) VALUES (20260120101402);
INSERT INTO public."schema_migrations" (version) VALUES (20260122172014);
INSERT INTO public."schema_migrations" (version) VALUES (20260202150634);
INSERT INTO public."schema_migrations" (version) VALUES (20260205162234);
INSERT INTO public."schema_migrations" (version) VALUES (20260213124416);
INSERT INTO public."schema_migrations" (version) VALUES (20260216120000);
INSERT INTO public."schema_migrations" (version) VALUES (20260218144340);
INSERT INTO public."schema_migrations" (version) VALUES (20260220120000);
