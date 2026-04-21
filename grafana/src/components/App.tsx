import React from 'react';
import { css } from '@emotion/css';
import { AppRootProps, GrafanaTheme2 } from '@grafana/data';
import { LinkButton, useStyles2 } from '@grafana/ui';
import { PLUGIN_ID, REQUIRED_SCOPE } from '../constants';
import { TuistAppJsonData } from '../types';

export const App = (props: AppRootProps<TuistAppJsonData>) => {
  const styles = useStyles2(getStyles);
  const meta = props.meta;
  const configured = Boolean(
    meta.jsonData?.accountHandle && meta.jsonData?.tuistUrl && meta.secureJsonFields?.metricsToken
  );

  return (
    <div className={styles.container}>
      <h2>Tuist metrics</h2>

      <p className={styles.lede}>
        Scrape per-account Xcode, Gradle, and CLI metrics from Tuist and view them in the bundled
        dashboards. No data is stored by this plugin — Alloy/Agent scrapes directly from the Tuist
        server and remote-writes to Prometheus.
      </p>

      <ol className={styles.steps}>
        <li>
          <strong>Mint a metrics token.</strong> In the Tuist dashboard, create an account token
          with the <code>{REQUIRED_SCOPE}</code> scope.
        </li>
        <li>
          <strong>Configure this plugin.</strong> Enter the server URL, account handle, token, and
          target Prometheus datasource on the <em>Configuration</em> tab.
        </li>
        <li>
          <strong>Deploy the scrape snippet.</strong> Copy the generated Alloy/Agent config and
          apply it to your collector. Pass the token via the <code>TUIST_METRICS_TOKEN</code>{' '}
          environment variable.
        </li>
        <li>
          <strong>Open the dashboards.</strong> Xcode builds, test reliability, cache
          effectiveness, and CLI usage are installed alongside the plugin.
        </li>
      </ol>

      <div className={styles.actions}>
        <LinkButton variant={configured ? 'secondary' : 'primary'} href={`/plugins/${PLUGIN_ID}`}>
          {configured ? 'Edit configuration' : 'Start setup'}
        </LinkButton>
        <LinkButton variant="secondary" href={`/dashboards/f/${PLUGIN_ID}`} icon="apps">
          Open dashboards
        </LinkButton>
      </div>
    </div>
  );
};

const getStyles = (theme: GrafanaTheme2) => ({
  container: css({
    padding: theme.spacing(3),
    maxWidth: theme.breakpoints.values.md,
  }),
  lede: css({
    color: theme.colors.text.secondary,
    marginBottom: theme.spacing(3),
  }),
  steps: css({
    display: 'flex',
    flexDirection: 'column',
    gap: theme.spacing(1.5),
    paddingInlineStart: theme.spacing(3),
    marginBottom: theme.spacing(3),
    code: {
      backgroundColor: theme.colors.background.secondary,
      padding: `0 ${theme.spacing(0.5)}`,
      borderRadius: theme.shape.radius.default,
    },
  }),
  actions: css({
    display: 'flex',
    gap: theme.spacing(1),
  }),
});
