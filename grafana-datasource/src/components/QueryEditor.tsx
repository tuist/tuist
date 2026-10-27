import React, { useEffect, useState } from 'react';

import { QueryEditorProps, SelectableValue } from '@grafana/data';
import { InlineField, InlineFieldRow, MultiSelect, RadioButtonGroup, Select } from '@grafana/ui';

import { BuildHealthQueryOptions } from './BuildHealthQueryOptions';
import { DataSource } from '../datasource';
import { TuistDataSourceOptions, TuistQuery, TuistQueryType, TuistSeries } from '../types';

type Props = QueryEditorProps<DataSource, TuistQuery, TuistDataSourceOptions>;

const queryTypeOptions: Array<SelectableValue<TuistQueryType>> = [
  { label: 'Xcode build durations', value: 'buildDuration' },
  { label: 'Test durations', value: 'testDuration' },
  { label: 'Build health', value: 'buildHealth' },
  { label: 'Health by workload', value: 'buildWorkloads' },
  { label: 'Failure reasons', value: 'buildFailureReasons' },
  { label: 'Recent failed builds', value: 'buildRecentFailures' },
];

const legacyQueryTypeOptions: Array<SelectableValue<TuistQueryType>> = [
  { label: 'Gradle build health', value: 'gradleHealth' },
  { label: 'Gradle health by workload', value: 'gradleWorkloads' },
  { label: 'Gradle failure reasons', value: 'gradleFailureReasons' },
  { label: 'Recent failed Gradle builds', value: 'gradleRecentFailures' },
];

const buildHealthQueryTypes: TuistQueryType[] = [
  'buildHealth', 'buildWorkloads', 'buildFailureReasons', 'buildRecentFailures',
  'gradleHealth', 'gradleWorkloads', 'gradleFailureReasons', 'gradleRecentFailures',
];

const seriesOptions: Array<SelectableValue<TuistSeries>> = [
  { label: 'Average', value: 'average' },
  { label: 'p50', value: 'p50' },
  { label: 'p90', value: 'p90' },
  { label: 'p99', value: 'p99' },
];

const environmentOptions: Array<SelectableValue<string>> = [
  { label: 'Any', value: 'any' },
  { label: 'CI', value: 'ci' },
  { label: 'Local', value: 'local' },
];

const statusOptions: Array<SelectableValue<string>> = [
  { label: 'Any', value: '' },
  { label: 'Success', value: 'success' },
  { label: 'Failure', value: 'failure' },
];

const categoryOptions: Array<SelectableValue<string>> = [
  { label: 'Any', value: '' },
  { label: 'Clean', value: 'clean' },
  { label: 'Incremental', value: 'incremental' },
];

export function QueryEditor({ query, onChange, onRunQuery, datasource }: Props) {
  const isBuildHealth = buildHealthQueryTypes.includes(query.queryType);
  const entity = query.queryType === 'testDuration' ? 'tests' : 'builds';

  const [projects, setProjects] = useState<Array<SelectableValue<string>>>([]);
  const [schemes, setSchemes] = useState<Array<SelectableValue<string>>>([]);
  const [configurations, setConfigurations] = useState<Array<SelectableValue<string>>>([]);

  useEffect(() => {
    datasource
      .getProjects()
      .then((items) => setProjects(items.map((p) => ({ label: p.full_name, value: p.full_name }))))
      .catch(() => setProjects([]));
  }, [datasource]);

  useEffect(() => {
    let active = true;
    if (isBuildHealth) {
      return;
    }
    datasource
      .getDimensionValues(entity, 'scheme', query.projectHandle ?? '')
      .then((items) => {
        if (active) {
          setSchemes(items.map((s) => ({ label: s, value: s })));
        }
      })
      .catch(() => {
        if (active) {
          setSchemes([]);
        }
      });
    return () => {
      active = false;
    };
  }, [datasource, entity, query.projectHandle, isBuildHealth]);

  useEffect(() => {
    let active = true;
    const load =
      !isBuildHealth && entity === 'builds' && query.projectHandle
        ? datasource.getDimensionValues('builds', 'configuration', query.projectHandle)
        : Promise.resolve<string[]>([]);
    load
      .then((items) => {
        if (active) {
          setConfigurations(items.map((c) => ({ label: c, value: c })));
        }
      })
      .catch(() => {
        if (active) {
          setConfigurations([]);
        }
      });
    return () => {
      active = false;
    };
  }, [datasource, entity, query.projectHandle, isBuildHealth]);

  const environment = query.environment ?? 'any';

  const update = (patch: Partial<TuistQuery>) => {
    onChange({ ...query, ...patch });
    onRunQuery();
  };

  return (
    <>
      <InlineFieldRow>
        <InlineField label="Query" labelWidth={16}>
          <Select
            width={28}
            options={[...queryTypeOptions, ...legacyQueryTypeOptions.filter((option) => option.value === query.queryType)]}
            value={query.queryType ?? 'buildDuration'}
            onChange={(v) => {
              const switchingBuildSystem = Boolean(isBuildHealth) !== Boolean(v.value && buildHealthQueryTypes.includes(v.value));
              update({
                queryType: v.value,
                ...(switchingBuildSystem
                  ? {
                      status: undefined,
                      scheme: undefined,
                      configuration: undefined,
                      category: undefined,
                      gitBranch: undefined,
                      workload: undefined,
                      metric: undefined,
                      slowBuildThresholdMs: undefined,
                    }
                  : {}),
              });
            }}
          />
        </InlineField>
        <InlineField label="Project" labelWidth={16} grow>
          <Select
            allowCustomValue
            options={projects}
            value={query.projectHandle ? { label: query.projectHandle, value: query.projectHandle } : undefined}
            placeholder="Select a project"
            onChange={(v) => update({ projectHandle: v.value })}
          />
        </InlineField>
      </InlineFieldRow>

      {isBuildHealth ? (
        <BuildHealthQueryOptions query={query} update={update} datasource={datasource} />
      ) : (
        <>
          <InlineFieldRow>
            <InlineField label="Result" labelWidth={16}>
              <RadioButtonGroup
                options={[
                  { label: 'Time series', value: 'series' },
                  { label: 'Whole period', value: 'total' },
                ]}
                value={query.resultMode ?? 'series'}
                onChange={(v) => update({ resultMode: v === 'total' ? 'total' : 'series' })}
              />
            </InlineField>
          </InlineFieldRow>
          <InlineFieldRow>
            <InlineField label="Series" labelWidth={16} grow>
              <MultiSelect
                options={seriesOptions}
                value={query.series ?? ['p50', 'p90', 'p99']}
                onChange={(values) => update({ series: values.map((v) => v.value!).filter(Boolean) as TuistSeries[] })}
              />
            </InlineField>
            <InlineField label="Environment" labelWidth={16}>
              <RadioButtonGroup
                options={environmentOptions}
                value={environment}
                onChange={(v) => update({ environment: v })}
              />
            </InlineField>
          </InlineFieldRow>

          <InlineFieldRow>
            <InlineField label="Scheme" labelWidth={16} grow>
              <Select
                isClearable
                options={schemes}
                value={query.scheme}
                placeholder="All schemes"
                onChange={(v) => update({ scheme: v?.value })}
              />
            </InlineField>
            {entity === 'builds' && (
              <InlineField label="Configuration" labelWidth={16} grow>
                <Select
                  isClearable
                  options={configurations}
                  value={query.configuration}
                  placeholder="All configurations"
                  onChange={(v) => update({ configuration: v?.value })}
                />
              </InlineField>
            )}
          </InlineFieldRow>

          {entity === 'builds' && (
            <InlineFieldRow>
              <InlineField label="Status" labelWidth={16}>
                <RadioButtonGroup
                  options={statusOptions}
                  value={query.status ?? ''}
                  onChange={(v) => update({ status: v })}
                />
              </InlineField>
              <InlineField label="Category" labelWidth={16}>
                <RadioButtonGroup
                  options={categoryOptions}
                  value={query.category ?? ''}
                  onChange={(v) => update({ category: v })}
                />
              </InlineField>
            </InlineFieldRow>
          )}
        </>
      )}
    </>
  );
}
