import { DataSource } from './datasource';
import { TuistQuery } from './types';

jest.mock('@grafana/runtime', () => ({
  DataSourceWithBackend: class {},
  getTemplateSrv: () => ({
    replace: (value: string) =>
      ({
        $project: 'sumup/android',
        $branch: '__tuist_all__',
        $workload: 'Unit tests',
      })[value] ?? value,
  }),
}));

test('Build-health filters interpolate dashboard variables and omit the All sentinel', () => {
  const query: TuistQuery = {
    refId: 'A',
    queryType: 'buildHealth',
    projectHandle: '$project',
    gitBranch: '$branch',
    workload: '$workload',
    metric: 'success_rate',
  };
  const result = DataSource.prototype.applyTemplateVariables(query, {});
  expect(result.projectHandle).toBe('sumup/android');
  expect(result.gitBranch).toBeUndefined();
  expect(result.workload).toBe('Unit tests');
  expect(result.metric).toBe('success_rate');
});

test('literal branches containing slashes stay intact', () => {
  const query: TuistQuery = { refId: 'A', queryType: 'buildHealth', gitBranch: 'release/next' };
  expect(DataSource.prototype.applyTemplateVariables(query, {}).gitBranch).toBe('release/next');
});

test('dimension dropdowns resolve the project variable before calling the backend', async () => {
  const datasource = Object.create(DataSource.prototype) as DataSource;
  const getResource = jest.fn().mockResolvedValue(['develop']);
  Object.defineProperty(datasource, 'getResource', { value: getResource });
  await expect(datasource.getDimensionValues('build-health', 'git_branch', '$project')).resolves.toEqual(['develop']);
  expect(getResource).toHaveBeenCalledWith('dimension-values', {
    entity: 'build-health',
    dimension: 'git_branch',
    project: 'sumup/android',
  });
});

test('existing duration defaults stay unchanged when Grafana fills missing query options', () => {
  expect(DataSource.prototype.getDefaultQuery(undefined!)).toEqual({
    queryType: 'buildDuration',
    series: ['average', 'p50', 'p90', 'p99'],
  });
});

test.each([
  ['buildSchemes', 'builds', 'scheme'],
  ['testSchemes', 'tests', 'scheme'],
  ['configurations', 'builds', 'configuration'],
  ['gradleBranches', 'gradle/builds', 'git_branch'],
  ['gradleWorkloads', 'gradle/builds', 'workload'],
])('saved %s variables retain their resource requests', async (kind, entity, dimension) => {
  const datasource = Object.create(DataSource.prototype) as DataSource;
  const getResource = jest.fn().mockResolvedValue(['existing-value']);
  Object.defineProperty(datasource, 'getResource', { value: getResource });
  await expect(datasource.metricFindQuery(`${kind} $project`)).resolves.toEqual([
    { text: 'existing-value', value: 'existing-value' },
  ]);
  expect(getResource).toHaveBeenCalledWith('dimension-values', {
    entity,
    dimension,
    project: 'sumup/android',
  });
});
