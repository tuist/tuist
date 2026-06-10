import { DataSourceJsonData } from '@grafana/data';
import { DataQuery } from '@grafana/schema';

export type TuistQueryType = 'buildDuration' | 'testDuration';

export type TuistSeries = 'average' | 'p50' | 'p90' | 'p99';

export interface TuistQuery extends DataQuery {
  queryType: TuistQueryType;
  // "account/project" handle, sourced from the projects resource.
  projectHandle?: string;
  series?: TuistSeries[];
  isCi?: boolean;
  scheme?: string;
  configuration?: string;
  category?: string;
  status?: string;
}

export const defaultQuery: Partial<TuistQuery> = {
  queryType: 'buildDuration',
  series: ['p50', 'p90', 'p99'],
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
