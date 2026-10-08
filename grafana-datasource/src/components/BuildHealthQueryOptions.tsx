import React, { useEffect, useState } from 'react';

import { SelectableValue } from '@grafana/data';
import { InlineField, InlineFieldRow, Input, RadioButtonGroup, Select } from '@grafana/ui';

import { DataSource } from '../datasource';
import { TuistQuery } from '../types';

export const buildMetrics = [
  { label: 'Build count', value: 'builds' },
  { label: 'Successful builds', value: 'successful_builds' },
  { label: 'Failed builds', value: 'failed_builds' },
  { label: 'Cancelled builds', value: 'cancelled_builds' },
  { label: 'Build success rate', value: 'success_rate' },
  { label: 'Average build duration', value: 'average' },
  { label: 'Median build duration', value: 'p50' },
  { label: '90th percentile build duration', value: 'p90' },
  { label: '99th percentile build duration', value: 'p99' },
  { label: 'Slow-build threshold', value: 'slow_build_threshold' },
  { label: 'Failed or slow builds', value: 'builds_needing_attention' },
  { label: 'Cumulative task time saved (Gradle)', value: 'cache_work_avoided' },
  { label: 'Builds reporting cumulative task time', value: 'cache_work_avoided_samples' },
  { label: 'Reported elapsed time saved', value: 'cache_time_saved' },
  { label: 'Builds reporting elapsed savings', value: 'cache_time_saved_samples' },
];

export function BuildHealthQueryOptions({
  query,
  update,
  datasource,
}: {
  query: TuistQuery;
  update: (patch: Partial<TuistQuery>) => void;
  datasource: DataSource;
}) {
  const [branches, setBranches] = useState<Array<SelectableValue<string>>>([]);
  const [workloads, setWorkloads] = useState<Array<SelectableValue<string>>>([]);

  useEffect(() => {
    let active = true;
    datasource
      .getDimensionValues(
        query.queryType.startsWith('gradle') ? 'gradle/builds' : 'build-health',
        'git_branch',
        query.projectHandle ?? ''
      )
      .then((items) => {
        if (active) {
          setBranches(items.map((value) => ({ label: value, value })));
        }
      })
      .catch(() => {
        if (active) {
          setBranches([]);
        }
      });
    datasource
      .getDimensionValues(
        query.queryType.startsWith('gradle') ? 'gradle/builds' : 'build-health',
        'workload',
        query.projectHandle ?? ''
      )
      .then((items) => {
        if (active) {
          setWorkloads(items.map((value) => ({ label: value, value })));
        }
      })
      .catch(() => {
        if (active) {
          setWorkloads([]);
        }
      });
    return () => {
      active = false;
    };
  }, [datasource, query.projectHandle, query.queryType]);

  return (
    <>
      {(query.queryType === 'gradleHealth' || query.queryType === 'buildHealth') && (
        <InlineFieldRow>
          <InlineField label="Metric" labelWidth={16} grow>
            <Select
              options={
                query.queryType === 'gradleHealth'
                  ? buildMetrics.filter((option) => !option.value.startsWith('cache_work_avoided'))
                  : buildMetrics
              }
              value={query.metric ?? 'p50'}
              onChange={(v) => update({ metric: v.value })}
            />
          </InlineField>
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
      )}
      <InlineFieldRow>
        <InlineField label="Environment" labelWidth={16}>
          <Select
            allowCustomValue
            width={28}
            options={[
              { label: 'Any', value: 'any' },
              { label: 'Automated', value: 'ci' },
              { label: 'Local', value: 'local' },
            ]}
            value={{ label: query.environment ?? 'any', value: query.environment ?? 'any' }}
            onChange={(v) => update({ environment: v.value })}
          />
        </InlineField>
        <InlineField label="Status" labelWidth={16}>
          <RadioButtonGroup
            options={[
              { label: 'Any', value: '' },
              { label: 'Success', value: 'success' },
              { label: 'Failure', value: 'failure' },
              { label: 'Cancelled', value: 'cancelled' },
            ]}
            value={query.status ?? ''}
            onChange={(v) => update({ status: v })}
          />
        </InlineField>
      </InlineFieldRow>
      <InlineFieldRow>
        <InlineField label="Branch" labelWidth={16} grow>
          <Select
            isClearable
            allowCustomValue
            options={branches}
            value={query.gitBranch ? { label: query.gitBranch, value: query.gitBranch } : undefined}
            placeholder="All branches"
            onChange={(v) => update({ gitBranch: v?.value })}
          />
        </InlineField>
        <InlineField label="Workload" labelWidth={16} grow>
          <Select
            isClearable
            allowCustomValue
            options={workloads}
            value={query.workload ? { label: query.workload, value: query.workload } : undefined}
            placeholder="All workloads"
            onChange={(v) => update({ workload: v?.value })}
          />
        </InlineField>
      </InlineFieldRow>
      {(query.queryType === 'gradleHealth' || query.queryType === 'buildHealth') && (
        <InlineFieldRow>
          <InlineField
            label="Slow threshold"
            labelWidth={16}
            tooltip="Milliseconds. Leave empty to use the 90th percentile of builds in the selected date range."
          >
            <Input
              width={32}
              type="number"
              min={0}
              max={31536000000}
              value={query.slowBuildThresholdMs ?? ''}
              placeholder="Automatic (90th percentile)"
              onChange={(event) => {
                const value = event.currentTarget.value;
                if (
                  value === '' ||
                  (Number.isSafeInteger(Number(value)) && Number(value) >= 0 && Number(value) <= 31536000000)
                ) {
                  update({ slowBuildThresholdMs: value === '' ? undefined : Number(value) });
                }
              }}
            />
          </InlineField>
        </InlineFieldRow>
      )}
    </>
  );
}
