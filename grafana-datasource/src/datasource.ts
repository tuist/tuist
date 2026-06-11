import { CoreApp, DataSourceInstanceSettings, MetricFindValue, ScopedVars } from '@grafana/data';
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

  async getDimensionValues(entity: 'builds' | 'tests', dimension: string, project: string): Promise<string[]> {
    if (!project) {
      return [];
    }
    return this.getResource('dimension-values', { entity, dimension, project });
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

  // Backs dashboard "query" variables. Supported queries:
  //   projects | buildSchemes <project> | testSchemes <project> | configurations <project>
  async metricFindQuery(query: string): Promise<MetricFindValue[]> {
    const interpolated = getTemplateSrv().replace(query ?? '');
    const [kind, ...rest] = interpolated.trim().split(/\s+/);
    const project = rest.join(' ');
    const toValues = (items: string[]) => items.map((item) => ({ text: item, value: item }));

    switch (kind) {
      case '':
      case 'projects':
        return (await this.getProjects()).map((p) => ({ text: p.full_name, value: p.full_name }));
      case 'buildSchemes':
        return toValues(await this.getDimensionValues('builds', 'scheme', project));
      case 'testSchemes':
        return toValues(await this.getDimensionValues('tests', 'scheme', project));
      case 'configurations':
        return toValues(await this.getDimensionValues('builds', 'configuration', project));
      default:
        return [];
    }
  }
}
