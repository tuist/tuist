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
        Track Xcode, Gradle, and CLI build performance in your Tuist account with the bundled
        dashboards. The plugin stores no data — Alloy/Agent scrapes Tuist's{' '}
        <code>/metrics</code> endpoint directly and remote-writes to Prometheus.
      </p>

      <ol className={styles.steps}>
        <li>
          <strong>Create a metrics token.</strong> Run{' '}
          <code>tuist account tokens create &lt;handle&gt; --scopes {REQUIRED_SCOPE} --name grafana</code>{' '}
          and copy the printed token.
        </li>
        <li>
          <strong>Configure this plugin.</strong> Enter the server URL, account handle, and token
          on the <em>Configuration</em> tab.
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
