import { CoreApp, DataSourceInstanceSettings, ScopedVars } from '@grafana/data';
import { DataSourceWithBackend, getTemplateSrv } from '@grafana/runtime';

import { defaultQuery, TuistDataSourceOptions, TuistProject, TuistQuery } from './types';

export class DataSource extends DataSourceWithBackend<TuistQuery, TuistDataSourceOptions> {
  constructor(instanceSettings: DataSourceInstanceSettings<TuistDataSourceOptions>) {
    super(instanceSettings);
  }

  getDefaultQuery(_app: CoreApp): Partial<TuistQuery> {
    return defaultQuery;
  }

  // The resource calls below are proxied through the backend so the account
  // token stays server-side.
  async getProjects(): Promise<TuistProject[]> {
    return this.getResource('projects');
  }

  async getSchemes(entity: 'builds' | 'tests', project: string): Promise<string[]> {
    if (!project) {
      return [];
    }
    return this.getResource('schemes', { entity, project });
  }

  async getConfigurations(project: string): Promise<string[]> {
    if (!project) {
      return [];
    }
    return this.getResource('configurations', { project });
  }

  filterQuery(query: TuistQuery): boolean {
    return Boolean(query.projectHandle);
  }

  applyTemplateVariables(query: TuistQuery, scopedVars: ScopedVars): TuistQuery {
    const srv = getTemplateSrv();
    const replace = (value?: string) => (value ? srv.replace(value, scopedVars) : value);
    return {
      ...query,
      projectHandle: replace(query.projectHandle),
      environment: replace(query.environment),
      scheme: replace(query.scheme),
      configuration: replace(query.configuration),
    };
  }
}
