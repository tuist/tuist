import React, { useMemo } from 'react';
import { css } from '@emotion/css';
import { GrafanaTheme2 } from '@grafana/data';
import { CodeEditor, useStyles2 } from '@grafana/ui';

interface Props {
  tuistUrl: string;
  accountHandle: string;
  scrapeInterval: string;
}

export const ScrapeSnippet = ({ tuistUrl, accountHandle, scrapeInterval }: Props) => {
  const styles = useStyles2(getStyles);

  const snippet = useMemo(
    () => renderAlloyConfig({ tuistUrl, accountHandle, scrapeInterval }),
    [tuistUrl, accountHandle, scrapeInterval]
  );

  return (
    <div className={styles.wrapper}>
      <CodeEditor
        value={snippet}
        language="hcl"
        showLineNumbers
        height={320}
        monacoOptions={{ readOnly: true, wordWrap: 'off' }}
      />
    </div>
  );
};

interface Input {
  tuistUrl: string;
  accountHandle: string;
  scrapeInterval: string;
}

function renderAlloyConfig({ tuistUrl, accountHandle, scrapeInterval }: Input): string {
  const { host, scheme } = parseHostAndScheme(tuistUrl);

  // We intentionally emit Alloy configuration rather than a Prometheus
  // scrape_config — Alloy is Grafana's recommended collector going forward,
  // and the generated blocks translate 1:1 to Grafana Agent flow mode.
  return [
    `// Grafana Alloy configuration for scraping Tuist's per-account /metrics endpoint.`,
    `// Export the token as TUIST_METRICS_TOKEN on the process that runs Alloy.`,
    ``,
    `prometheus.scrape "tuist_${sanitizeHandle(accountHandle)}" {`,
    `  targets = [{`,
    `    __address__ = "${host}",`,
    `    __scheme__  = "${scheme}",`,
    `  }]`,
    ``,
    `  metrics_path    = "/api/accounts/${accountHandle}/metrics"`,
    `  scrape_interval = "${scrapeInterval}"`,
    `  bearer_token    = sys.env("TUIST_METRICS_TOKEN")`,
    ``,
    `  forward_to = [prometheus.remote_write.grafana_cloud.receiver]`,
    `}`,
    ``,
    `prometheus.remote_write "grafana_cloud" {`,
    `  endpoint {`,
    `    url = sys.env("GRAFANA_CLOUD_PROM_URL")`,
    `    basic_auth {`,
    `      username = sys.env("GRAFANA_CLOUD_PROM_USER")`,
    `      password = sys.env("GRAFANA_CLOUD_PROM_API_KEY")`,
    `    }`,
    `  }`,
    `}`,
    ``,
  ].join('\n');
}

function parseHostAndScheme(rawUrl: string): { host: string; scheme: 'http' | 'https' } {
  try {
    const url = new URL(rawUrl);
    const scheme = url.protocol === 'http:' ? 'http' : 'https';
    const host = url.port ? `${url.hostname}:${url.port}` : `${url.hostname}:${scheme === 'http' ? 80 : 443}`;
    return { host, scheme };
  } catch {
    // Fall back to the raw host with HTTPS, which is what Tuist Cloud uses.
    return { host: rawUrl.replace(/^https?:\/\//, ''), scheme: 'https' };
  }
}

function sanitizeHandle(handle: string): string {
  return handle.replace(/[^a-z0-9_]/gi, '_').toLowerCase() || 'account';
}

const getStyles = (theme: GrafanaTheme2) => ({
  wrapper: css({
    border: `1px solid ${theme.colors.border.weak}`,
    borderRadius: theme.shape.radius.default,
    overflow: 'hidden',
  }),
});
