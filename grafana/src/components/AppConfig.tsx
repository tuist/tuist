import React, { ChangeEvent, useMemo, useState } from 'react';
import { css } from '@emotion/css';
import { AppPluginMeta, GrafanaTheme2, PluginConfigPageProps, PluginMeta } from '@grafana/data';
import { getBackendSrv } from '@grafana/runtime';
import {
  Alert,
  Button,
  DataSourcePicker,
  Field,
  FieldSet,
  Input,
  SecretInput,
  useStyles2,
} from '@grafana/ui';
import { lastValueFrom } from 'rxjs';
import { DEFAULT_SCRAPE_INTERVAL, DEFAULT_TUIST_URL, PLUGIN_ID, REQUIRED_SCOPE } from '../constants';
import { TuistAppJsonData, TuistAppSecureJsonData, TuistAppSecureJsonFields } from '../types';
import { ScrapeSnippet } from './ScrapeSnippet';

type Meta = PluginMeta<TuistAppJsonData> & {
  secureJsonFields?: TuistAppSecureJsonFields;
};

type Props = PluginConfigPageProps<AppPluginMeta<TuistAppJsonData>> & {
  plugin: { meta: Meta };
};

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

  const onChange =
    (key: keyof State) =>
    (event: ChangeEvent<HTMLInputElement>) =>
      setState((prev) => ({ ...prev, [key]: event.currentTarget.value, saved: false }));

  const readyForSnippet = useMemo(
    () =>
      state.accountHandle.length > 0 &&
      state.tuistUrl.length > 0 &&
      (state.tokenConfigured || state.metricsToken.length > 0),
    [state.accountHandle, state.tuistUrl, state.tokenConfigured, state.metricsToken]
  );

  const onSubmit = async () => {
    setState((s) => ({ ...s, saving: true, saveError: undefined, saved: false }));

    try {
      await updatePluginSettings({
        enabled: true,
        pinned: true,
        jsonData: {
          tuistUrl: state.tuistUrl.trim().replace(/\/+$/, ''),
          accountHandle: state.accountHandle.trim(),
          scrapeInterval: state.scrapeInterval.trim() || DEFAULT_SCRAPE_INTERVAL,
          prometheusDatasourceUid: state.prometheusDatasourceUid.trim(),
        },
        // Only write the token when the user enters a new one; leave the
        // existing secret in place otherwise.
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
        <Field
          label="Server URL"
          description="The root URL of your Tuist server. Omit the trailing slash."
        >
          <Input
            width={60}
            placeholder="https://tuist.dev"
            value={state.tuistUrl}
            onChange={onChange('tuistUrl')}
          />
        </Field>

        <Field
          label="Account handle"
          description="The user or organisation handle whose metrics you want to scrape."
          required
        >
          <Input
            width={60}
            placeholder="acme"
            value={state.accountHandle}
            onChange={onChange('accountHandle')}
          />
        </Field>

        <Field
          label="Metrics token"
          description={`Bearer account token carrying the \`${REQUIRED_SCOPE}\` scope. Mint one with \`POST /api/accounts/:handle/tokens\`.`}
          required={!state.tokenConfigured}
        >
          <SecretInput
            width={60}
            isConfigured={state.tokenConfigured}
            placeholder="tuist_<id>_<hash>"
            value={state.metricsToken}
            onChange={onChange('metricsToken')}
            onReset={() => setState((s) => ({ ...s, tokenConfigured: false, metricsToken: '' }))}
          />
        </Field>
      </FieldSet>

      <FieldSet label="Scrape settings">
        <Field
          label="Scrape interval"
          description="Must stay above 10s — the server rate-limits per account."
        >
          <Input
            width={20}
            placeholder="15s"
            value={state.scrapeInterval}
            onChange={onChange('scrapeInterval')}
          />
        </Field>

        <Field
          label="Prometheus datasource"
          description="Datasource that Alloy/Agent remote-writes scraped metrics into. The bundled dashboards query it by UID."
        >
          <DataSourcePicker
            current={state.prometheusDatasourceUid || null}
            onChange={(ds) =>
              setState((s) => ({ ...s, prometheusDatasourceUid: ds?.uid ?? '', saved: false }))
            }
            type="prometheus"
            noDefault
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
          Now copy the scrape snippet below into your Alloy/Agent config and reload the collector.
        </Alert>
      ) : null}

      <div className={styles.actions}>
        <Button type="submit" onClick={onSubmit} disabled={state.saving}>
          {state.saving ? 'Saving...' : 'Save settings'}
        </Button>
      </div>

      {readyForSnippet ? (
        <FieldSet label="Collector snippet">
          <p className={styles.helpText}>
            Paste this into your Grafana Alloy or Grafana Agent configuration. The token is stored
            securely; reference it from an environment variable so it never lands in source control.
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

