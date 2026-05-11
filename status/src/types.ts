export type IncidentSeverity = "minor" | "major" | "critical" | "maintenance";

export type IncidentStatus = "investigating" | "identified" | "monitoring" | "resolved";

export type ComponentStatus =
  | "operational"
  | "degraded_performance"
  | "partial_outage"
  | "major_outage"
  | "under_maintenance";

export type OverallStatus = ComponentStatus;

export interface IncidentUpdate {
  at: string;
  status: IncidentStatus;
  body: string;
}

export interface Incident {
  id: string;
  title: string;
  severity: IncidentSeverity;
  status: IncidentStatus;
  affectedComponents: string[];
  startedAt: string;
  resolvedAt: string | null;
  updates: IncidentUpdate[];
}

export interface Component {
  id: string;
  name: string;
  description: string;
  status: ComponentStatus;
}

export interface StatusSnapshot {
  overall: OverallStatus;
  components: Component[];
  activeIncidents: Incident[];
  recentIncidents: Incident[];
  fetchedAt: string;
}

export interface Env {
  USE_FAKE_DATA: string;
  STATUS_PAGE_TITLE: string;
  GRAFANA_INCIDENT_API_URL: string;
  GRAFANA_INCIDENT_API_TOKEN?: string;
  // Name (or slug) of the Grafana Incident label field whose select options
  // define the public components shown on the status page.
  GRAFANA_COMPONENT_LABEL_KEY: string;
  // When set to "true", exposes /api/debug/* routes that return raw upstream
  // Grafana responses. Unset by default — debug routes return 404 in production.
  ENABLE_DEBUG_ROUTES?: string;
}
