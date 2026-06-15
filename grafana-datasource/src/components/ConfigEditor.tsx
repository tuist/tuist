import React, { ChangeEvent } from 'react';

import { DataSourcePluginOptionsEditorProps } from '@grafana/data';
import { InlineField, Input, SecretInput } from '@grafana/ui';

import { TuistDataSourceOptions, TuistSecureJsonData } from '../types';

interface Props extends DataSourcePluginOptionsEditorProps<TuistDataSourceOptions, TuistSecureJsonData> {}

export function ConfigEditor(props: Props) {
  const { onOptionsChange, options } = props;
  const { jsonData, secureJsonFields, secureJsonData } = options;

  const onUrlChange = (event: ChangeEvent<HTMLInputElement>) => {
    onOptionsChange({
      ...options,
      jsonData: { ...jsonData, url: event.target.value },
    });
  };

  const onTokenChange = (event: ChangeEvent<HTMLInputElement>) => {
    onOptionsChange({
      ...options,
      secureJsonData: { ...secureJsonData, apiToken: event.target.value },
    });
  };

  const onResetToken = () => {
    onOptionsChange({
      ...options,
      secureJsonFields: { ...secureJsonFields, apiToken: false },
      secureJsonData: { ...secureJsonData, apiToken: '' },
    });
  };

  return (
    <>
      <InlineField label="Server URL" labelWidth={16} tooltip="Tuist server URL. Defaults to https://tuist.dev.">
        <Input
          width={40}
          value={jsonData.url ?? ''}
          placeholder="https://tuist.dev"
          onChange={onUrlChange}
        />
      </InlineField>

      <InlineField
        label="Account token"
        labelWidth={16}
        tooltip="A Tuist account token with project:builds:read and project:tests:read scopes (both covered by the 'mcp' scope group)."
      >
        <SecretInput
          width={40}
          isConfigured={Boolean(secureJsonFields?.apiToken)}
          value={secureJsonData?.apiToken ?? ''}
          placeholder="tuist_..."
          onChange={onTokenChange}
          onReset={onResetToken}
        />
      </InlineField>
    </>
  );
}
