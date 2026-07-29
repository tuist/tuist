import React, { useEffect, useState } from 'react';

import { QueryEditorProps, SelectableValue } from '@grafana/data';
import { InlineField, InlineFieldRow, MultiSelect, RadioButtonGroup, Select } from '@grafana/ui';

import { DataSource } from '../datasource';
import { TuistDataSourceOptions, TuistQuery, TuistQueryType, TuistSeries } from '../types';

type Props = QueryEditorProps<DataSource, TuistQuery, TuistDataSourceOptions>;

const queryTypeOptions: Array<SelectableValue<TuistQueryType>> = [
  { label: 'Build durations', value: 'buildDuration' },
  { label: 'Test durations', value: 'testDuration' },
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
  }, [datasource, entity, query.projectHandle]);

  useEffect(() => {
    let active = true;
    const load =
      entity === 'builds' && query.projectHandle
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
  }, [datasource, entity, query.projectHandle]);

  const environment = query.environment ?? 'any';

  const update = (patch: Partial<TuistQuery>) => {
    onChange({ ...query, ...patch });
    onRunQuery();
  };

  return (
    <>
      <InlineFieldRow>
        <InlineField label="Metric" labelWidth={16}>
          <Select
            width={28}
            options={queryTypeOptions}
            value={query.queryType ?? 'buildDuration'}
            onChange={(v) => update({ queryType: v.value })}
          />
        </InlineField>
        <InlineField label="Project" labelWidth={16} grow>
          <Select
            options={projects}
            value={query.projectHandle}
            placeholder="Select a project"
            onChange={(v) => update({ projectHandle: v.value })}
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
  );
}
