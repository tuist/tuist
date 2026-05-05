import type {
  Component,
  ComponentStatus,
  Incident,
  IncidentSeverity,
  IncidentStatus,
  IncidentUpdate,
  OverallStatus,
  StatusSnapshot,
} from "./types.js";

// The Grafana Incident API is a Twirp-style JSON-over-HTTP RPC surface. Every
// method is POST <base>/api/v1/<Service>.<Method> with a JSON body and these
// headers:
//
//   Authorization: Bearer <glsa_...>
//   Content-Type: application/json; charset=utf-8
//
// The base URL must be the per-stack proxy form
// (https://<stack>.grafana.net/api/plugins/grafana-irm-app/resources) — the
// regional `incident-prod-*.grafana.net` host rejects stack-scoped service
// account tokens with "legacy auth cannot be upgraded".
//
// Reference: https://grafana.com/docs/grafana-cloud/alerting-and-irm/incident/api/

interface RawIncident {
  incidentID: string;
  title: string;
  severity?: string;
  status?: string;
  isDrill?: boolean;
  createdTime?: string;
  modifiedTime?: string;
  closedTime?: string | null;
  summary?: string;
  incidentStart?: string;
  incidentEnd?: string | null;
  severityLabel?: string;
  labels?: RawLabel[];
}

interface RawLabel {
  // Grafana Incident labels are typically `{ label: { key, value } }` when
  // returned from QueryIncidents. Both shapes are tolerated below.
  label?: { key?: string; value?: string };
  key?: string;
  value?: string;
}

interface RawFieldSelectOption {
  uuid?: string;
  value?: string;
  label?: string;
  description?: string;
  color?: string;
  icon?: string;
}

interface RawField {
  uuid?: string;
  name?: string;
  slug?: string;
  domainName?: string;
  archived?: boolean;
  selectoptions?: RawFieldSelectOption[];
}

interface QueryIncidentsResponse {
  error?: string;
  incidents?: RawIncident[];
  cursor?: { hasMore: boolean; nextValue: string };
}

interface GetFieldsResponse {
  error?: string;
  fields?: RawField[];
}

const SEVERITY_MAP: Record<string, IncidentSeverity> = {
  pending: "minor",
  minor: "minor",
  major: "major",
  critical: "critical",
};

function severityFrom(input: string | undefined, labels: RawLabel[] = []): IncidentSeverity {
  if (labels.some((l) => labelValue(l)?.toLowerCase() === "maintenance")) return "maintenance";
  if (!input) return "minor";
  return SEVERITY_MAP[input.toLowerCase()] ?? "minor";
}

function statusFrom(input: string | undefined): IncidentStatus {
  if (!input) return "investigating";
  return input.toLowerCase() === "resolved" ? "resolved" : "investigating";
}

function labelKey(l: RawLabel): string | undefined {
  return l.label?.key ?? l.key;
}

function labelValue(l: RawLabel): string | undefined {
  return l.label?.value ?? l.value;
}

function affectedComponentsFrom(
  labels: RawLabel[] | undefined,
  componentLabelKey: string,
  knownIds: Set<string>,
): string[] {
  if (!labels) return [];
  const wanted = componentLabelKey.toLowerCase();
  const ids = new Set<string>();
  for (const l of labels) {
    const key = labelKey(l)?.toLowerCase();
    const value = labelValue(l);
    if (key === wanted && value && knownIds.has(value)) ids.add(value);
  }
  return Array.from(ids);
}

function toIncident(raw: RawIncident, componentLabelKey: string, knownIds: Set<string>): Incident {
  const updates: IncidentUpdate[] = [];
  if (raw.summary) {
    updates.push({
      at: raw.modifiedTime ?? raw.createdTime ?? new Date().toISOString(),
      status: statusFrom(raw.status),
      body: raw.summary,
    });
  }
  return {
    id: raw.incidentID,
    title: raw.title,
    severity: severityFrom(raw.severity, raw.labels),
    status: statusFrom(raw.status),
    affectedComponents: affectedComponentsFrom(raw.labels, componentLabelKey, knownIds),
    startedAt: raw.incidentStart ?? raw.createdTime ?? new Date().toISOString(),
    resolvedAt: raw.closedTime ?? raw.incidentEnd ?? null,
    updates,
  };
}

const SEVERITY_RANK: Record<IncidentSeverity, number> = {
  maintenance: 0,
  minor: 1,
  major: 2,
  critical: 3,
};

function severityToComponentStatus(s: IncidentSeverity): ComponentStatus {
  switch (s) {
    case "maintenance":
      return "under_maintenance";
    case "minor":
      return "degraded_performance";
    case "major":
      return "partial_outage";
    case "critical":
      return "major_outage";
  }
}

function rollUpComponents(defs: Omit<Component, "status">[], active: Incident[]): Component[] {
  const worst = new Map<string, IncidentSeverity>();
  for (const i of active) {
    for (const id of i.affectedComponents) {
      const cur = worst.get(id);
      if (!cur || SEVERITY_RANK[i.severity] > SEVERITY_RANK[cur]) worst.set(id, i.severity);
    }
  }
  return defs.map((c) => ({
    ...c,
    status: worst.has(c.id) ? severityToComponentStatus(worst.get(c.id)!) : "operational",
  }));
}

function rollUpOverall(components: Component[]): OverallStatus {
  const order: ComponentStatus[] = [
    "major_outage",
    "partial_outage",
    "degraded_performance",
    "under_maintenance",
    "operational",
  ];
  for (const status of order) {
    if (components.some((c) => c.status === status)) return status;
  }
  return "operational";
}

interface ClientOpts {
  baseUrl: string;
  token: string;
}

async function rpc<T>(opts: ClientOpts, method: string, body: object): Promise<T> {
  const url = `${opts.baseUrl.replace(/\/$/, "")}/api/v1/${method}`;
  const response = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${opts.token}`,
      "Content-Type": "application/json; charset=utf-8",
    },
    body: JSON.stringify(body),
  });
  const text = await response.text();
  if (!response.ok) {
    throw new Error(`Grafana Incident ${method} returned ${response.status}: ${text.slice(0, 500)}`);
  }
  let json: { error?: string } & T;
  try {
    json = JSON.parse(text) as { error?: string } & T;
  } catch {
    throw new Error(`Grafana Incident ${method} returned non-JSON: ${text.slice(0, 500)}`);
  }
  if (json.error) {
    throw new Error(`Grafana Incident ${method} returned error: ${json.error}`);
  }
  return json;
}

async function queryIncidents(opts: ClientOpts, queryString: string, limit = 100): Promise<RawIncident[]> {
  const out: RawIncident[] = [];
  let cursor: string | undefined;
  for (let page = 0; page < 5; page++) {
    const body: Record<string, unknown> = { query: { queryString, limit, orderDirection: "DESC" } };
    if (cursor) (body.query as Record<string, unknown>).cursor = cursor;
    const res = await rpc<QueryIncidentsResponse>(opts, "IncidentsService.QueryIncidents", body);
    const batch = res.incidents ?? [];
    out.push(...batch);
    if (!res.cursor?.hasMore) break;
    cursor = res.cursor.nextValue;
  }
  return out;
}

function withinLastDays(iso: string | null | undefined, days: number): boolean {
  if (!iso) return false;
  const t = Date.parse(iso);
  if (Number.isNaN(t)) return false;
  return Date.now() - t <= days * 24 * 60 * 60_000;
}

async function fetchComponentDefinitions(opts: ClientOpts, labelKey: string): Promise<Omit<Component, "status">[]> {
  const res = await rpc<GetFieldsResponse>(opts, "FieldsService.GetFields", {
    domainName: "labels",
  });
  const fields = res.fields ?? [];
  const wanted = labelKey.toLowerCase();
  const field = fields.find(
    (f) => !f.archived && (f.name?.toLowerCase() === wanted || f.slug?.toLowerCase() === wanted),
  );
  if (!field) return [];
  return (field.selectoptions ?? [])
    .filter((opt) => typeof opt.value === "string" && opt.value.length > 0)
    .map((opt) => ({
      id: opt.value!,
      name: opt.label?.trim() || opt.value!,
      description: opt.description?.trim() ?? "",
    }));
}

export interface RawSnapshot {
  componentField: RawField | null;
  active: RawIncident[];
  recent: RawIncident[];
}

export async function fetchRawFields(env: {
  GRAFANA_INCIDENT_API_URL: string;
  GRAFANA_INCIDENT_API_TOKEN?: string;
}): Promise<RawField[]> {
  if (!env.GRAFANA_INCIDENT_API_TOKEN) {
    throw new Error("GRAFANA_INCIDENT_API_TOKEN is not set");
  }
  const opts: ClientOpts = {
    baseUrl: env.GRAFANA_INCIDENT_API_URL,
    token: env.GRAFANA_INCIDENT_API_TOKEN,
  };
  const res = await rpc<GetFieldsResponse>(opts, "FieldsService.GetFields", {
    domainName: "labels",
  });
  return res.fields ?? [];
}

export async function fetchRawIncidents(env: {
  GRAFANA_INCIDENT_API_URL: string;
  GRAFANA_INCIDENT_API_TOKEN?: string;
  GRAFANA_COMPONENT_LABEL_KEY: string;
}): Promise<RawSnapshot> {
  if (!env.GRAFANA_INCIDENT_API_TOKEN) {
    throw new Error("GRAFANA_INCIDENT_API_TOKEN is not set");
  }
  const opts: ClientOpts = {
    baseUrl: env.GRAFANA_INCIDENT_API_URL,
    token: env.GRAFANA_INCIDENT_API_TOKEN,
  };
  const wanted = env.GRAFANA_COMPONENT_LABEL_KEY.toLowerCase();
  const [fieldsRes, active, recentAll] = await Promise.all([
    rpc<GetFieldsResponse>(opts, "FieldsService.GetFields", { domainName: "labels" }),
    queryIncidents(opts, "isdrill:false status:active"),
    queryIncidents(opts, "isdrill:false status:resolved"),
  ]);
  const componentField =
    (fieldsRes.fields ?? []).find(
      (f) => !f.archived && (f.name?.toLowerCase() === wanted || f.slug?.toLowerCase() === wanted),
    ) ?? null;
  const recent = recentAll.filter((i) => withinLastDays(i.closedTime ?? i.incidentEnd ?? i.modifiedTime, 14));
  return { componentField, active, recent };
}

export async function fetchStatusFromGrafana(env: {
  GRAFANA_INCIDENT_API_URL: string;
  GRAFANA_INCIDENT_API_TOKEN?: string;
  GRAFANA_COMPONENT_LABEL_KEY: string;
}): Promise<StatusSnapshot> {
  if (!env.GRAFANA_INCIDENT_API_TOKEN) {
    throw new Error("GRAFANA_INCIDENT_API_TOKEN is not set");
  }
  const opts: ClientOpts = {
    baseUrl: env.GRAFANA_INCIDENT_API_URL,
    token: env.GRAFANA_INCIDENT_API_TOKEN,
  };
  const [defs, active, recentAll] = await Promise.all([
    fetchComponentDefinitions(opts, env.GRAFANA_COMPONENT_LABEL_KEY),
    queryIncidents(opts, "isdrill:false status:active"),
    queryIncidents(opts, "isdrill:false status:resolved"),
  ]);
  const knownIds = new Set(defs.map((d) => d.id));
  const activeIncidents = active.map((r) => toIncident(r, env.GRAFANA_COMPONENT_LABEL_KEY, knownIds));
  const recentIncidents = recentAll
    .filter((i) => withinLastDays(i.closedTime ?? i.incidentEnd ?? i.modifiedTime, 14))
    .map((r) => toIncident(r, env.GRAFANA_COMPONENT_LABEL_KEY, knownIds));
  const components = rollUpComponents(defs, activeIncidents);
  return {
    overall: rollUpOverall(components),
    components,
    activeIncidents,
    recentIncidents,
    fetchedAt: new Date().toISOString(),
  };
}
