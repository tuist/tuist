import { DataSourceJsonData } from '@grafana/data';
import { DataQuery } from '@grafana/schema';

export type TuistQueryType =
  | 'buildDuration'
  | 'testDuration'
  | 'buildHealth'
  | 'buildWorkloads'
  | 'buildFailureReasons'
  | 'buildRecentFailures'
  | 'gradleHealth'
  | 'gradleWorkloads'
  | 'gradleFailureReasons'
  | 'gradleRecentFailures';

export type TuistSeries = 'average' | 'p50' | 'p90' | 'p99';

// Where the run executed. Mirrors the Tuist dashboard's Environment filter.
// A template variable (e.g. "$environment") is also accepted.
export type TuistEnvironment = 'any' | 'ci' | 'local';

export interface TuistQuery extends DataQuery {
  queryType: TuistQueryType;
  // "account/project" handle, sourced from the projects resource.
  projectHandle?: string;
  series?: TuistSeries[];
  environment?: string;
  scheme?: string;
  configuration?: string;
  category?: string;
  status?: string;
  resultMode?: 'series' | 'total';
  metric?: string;
  gitBranch?: string;
  workload?: string;
  slowBuildThresholdMs?: number;
}

export const defaultQuery: Partial<TuistQuery> = {
  queryType: 'buildDuration',
  series: ['average', 'p50', 'p90', 'p99'],
};

// Non-secret options stored as jsonData.
export interface TuistDataSourceOptions extends DataSourceJsonData {
  url?: string;
}

// Secret options stored as secureJsonData (encrypted at rest, never sent to the browser).
export interface TuistSecureJsonData {
  apiToken?: string;
}

export interface TuistProject {
  full_name: string;
}
