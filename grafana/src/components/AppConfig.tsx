import React, { ChangeEvent, useMemo, useState } from 'react';
import { css } from '@emotion/css';
import { AppPluginMeta, GrafanaTheme2, PluginConfigPageProps, SelectableValue } from '@grafana/data';
import { getBackendSrv, getDataSourceSrv } from '@grafana/runtime';
import {
  Alert,
  Button,
  Field,
  FieldSet,
  Input,
  SecretInput,
  Select,
  useStyles2,
} from '@grafana/ui';
import { lastValueFrom } from 'rxjs';
import { DEFAULT_SCRAPE_INTERVAL, DEFAULT_TUIST_URL, PLUGIN_ID, REQUIRED_SCOPE } from '../constants';
import { TuistAppJsonData, TuistAppSecureJsonData, TuistAppSecureJsonFields } from '../types';
import { ScrapeSnippet } from './ScrapeSnippet';

type Meta = AppPluginMeta<TuistAppJsonData> & {
  secureJsonFields?: TuistAppSecureJsonFields;
};

type Props = PluginConfigPageProps<Meta>;

interface State {
  tuistUrl: string;
  accountHandle: string;
  scrapeInterval: string;
  prometheusDatasourceUid: string;
  metricsToken: string;
  tokenConfigured: boolean;
  saving: boolean;
  saveError?: string;
  saved: boolean;
}

export const AppConfig = ({ plugin }: Props) => {
  const styles = useStyles2(getStyles);
  const { jsonData, secureJsonFields } = plugin.meta;

  const [state, setState] = useState<State>({
    tuistUrl: jsonData?.tuistUrl ?? DEFAULT_TUIST_URL,
    accountHandle: jsonData?.accountHandle ?? '',
    scrapeInterval: jsonData?.scrapeInterval ?? DEFAULT_SCRAPE_INTERVAL,
    prometheusDatasourceUid: jsonData?.prometheusDatasourceUid ?? '',
    metricsToken: '',
    tokenConfigured: Boolean(secureJsonFields?.metricsToken),
    saving: false,
    saved: false,
  });

  const prometheusOptions: Array<SelectableValue<string>> = useMemo(() => {
    // getDataSourceSrv().getList is stable across Grafana 10-12 and scoped
    // to the configured datasources. Filtering by type avoids pulling in
    // non-Prometheus datasources the dashboards cannot query.
    try {
      return getDataSourceSrv()
        .getList({ type: 'prometheus' })
        .map((ds) => ({ label: ds.name, value: ds.uid, description: ds.type }));
    } catch {
      return [];
    }
  }, []);

  const onInputChange =
    (key: keyof State) =>
    (event: ChangeEvent<HTMLInputElement>) =>
      setState((prev) => ({ ...prev, [key]: event.currentTarget.value, saved: false }));

  const readyForSnippet =
    state.accountHandle.length > 0 &&
    state.tuistUrl.length > 0 &&
    (state.tokenConfigured || state.metricsToken.length > 0);

  const onSubmit = async () => {
    setState((s) => ({ ...s, saving: true, saveError: undefined, saved: false }));

    try {
      await updatePluginSettings({
        enabled: plugin.meta.enabled ?? true,
        pinned: plugin.meta.pinned ?? true,
        jsonData: {
          tuistUrl: state.tuistUrl.trim().replace(/\/+$/, ''),
          accountHandle: state.accountHandle.trim(),
          scrapeInterval: state.scrapeInterval.trim() || DEFAULT_SCRAPE_INTERVAL,
          prometheusDatasourceUid: state.prometheusDatasourceUid.trim(),
        },
        // Only write the token when the user entered a new one; keep the
        // stored secret untouched otherwise.
        secureJsonData:
          state.metricsToken.length > 0 ? { metricsToken: state.metricsToken } : undefined,
      });

      setState((s) => ({
        ...s,
        saving: false,
        saved: true,
        metricsToken: '',
        tokenConfigured: s.tokenConfigured || state.metricsToken.length > 0,
      }));
    } catch (error) {
      setState((s) => ({
        ...s,
        saving: false,
        saveError: error instanceof Error ? error.message : 'Unable to save plugin settings.',
      }));
    }
  };

  return (
    <div className={styles.container}>
      <FieldSet label="Tuist server">
        <Field label="Server URL" description="Root URL of your Tuist server, no trailing slash.">
          <Input
            width={60}
            placeholder="https://tuist.dev"
            value={state.tuistUrl}
            onChange={onInputChange('tuistUrl')}
          />
        </Field>

        <Field
          label="Account handle"
          description="The user or organisation handle whose metrics you want to scrape."
        >
          <Input
            width={60}
            placeholder="acme"
            value={state.accountHandle}
            onChange={onInputChange('accountHandle')}
          />
        </Field>

        <Field
          label="Metrics token"
          description={`Bearer account token carrying the "${REQUIRED_SCOPE}" scope. Mint one via POST /api/accounts/:handle/tokens.`}
        >
          <SecretInput
            width={60}
            isConfigured={state.tokenConfigured}
            placeholder="tuist_<id>_<hash>"
            value={state.metricsToken}
            onChange={onInputChange('metricsToken')}
            onReset={() => setState((s) => ({ ...s, tokenConfigured: false, metricsToken: '' }))}
          />
        </Field>
      </FieldSet>

      <FieldSet label="Scrape settings">
        <Field
          label="Scrape interval"
          description="Stay above 10s — the server rate-limits scrapes per account."
        >
          <Input
            width={20}
            placeholder="15s"
            value={state.scrapeInterval}
            onChange={onInputChange('scrapeInterval')}
          />
        </Field>

        <Field
          label="Prometheus datasource"
          description="Datasource that Alloy/Agent remote-writes into. The bundled dashboards read from it."
        >
          <Select
            width={60}
            placeholder="Select a Prometheus datasource"
            options={prometheusOptions}
            value={state.prometheusDatasourceUid || null}
            onChange={(opt) =>
              setState((s) => ({ ...s, prometheusDatasourceUid: opt?.value ?? '', saved: false }))
            }
            isClearable
          />
        </Field>
      </FieldSet>

      {state.saveError ? (
        <Alert title="Could not save settings" severity="error">
          {state.saveError}
        </Alert>
      ) : null}

      {state.saved ? (
        <Alert title="Settings saved" severity="success">
          Paste the snippet below into your Alloy or Agent config, then reload the collector.
        </Alert>
      ) : null}

      <div className={styles.actions}>
        <Button onClick={onSubmit} disabled={state.saving}>
          {state.saving ? 'Saving...' : 'Save settings'}
        </Button>
      </div>

      {readyForSnippet ? (
        <FieldSet label="Collector snippet">
          <p className={styles.helpText}>
            The token is stored as a secret. Reference it from an environment variable in your
            collector config so it never lands in source control.
          </p>
          <ScrapeSnippet
            tuistUrl={state.tuistUrl}
            accountHandle={state.accountHandle}
            scrapeInterval={state.scrapeInterval || DEFAULT_SCRAPE_INTERVAL}
          />
        </FieldSet>
      ) : (
        <Alert title="Snippet available after setup" severity="info">
          Enter the server URL, account handle, and token, then save — the collector snippet will
          appear here.
        </Alert>
      )}
    </div>
  );
};

interface UpdateRequest {
  enabled: boolean;
  pinned: boolean;
  jsonData: TuistAppJsonData;
  secureJsonData?: TuistAppSecureJsonData;
}

async function updatePluginSettings(req: UpdateRequest) {
  const response = getBackendSrv().fetch({
    url: `/api/plugins/${PLUGIN_ID}/settings`,
    method: 'POST',
    data: req,
  });
  await lastValueFrom(response);
}

const getStyles = (theme: GrafanaTheme2) => ({
  container: css({
    display: 'flex',
    flexDirection: 'column',
    gap: theme.spacing(2),
    maxWidth: theme.breakpoints.values.lg,
  }),
  actions: css({
    display: 'flex',
    justifyContent: 'flex-start',
  }),
  helpText: css({
    color: theme.colors.text.secondary,
    marginBottom: theme.spacing(1),
  }),
});
