import React from 'react';
import { render } from '@testing-library/react';
import { ScrapeSnippet } from './ScrapeSnippet';

// The snippet renders inside @grafana/ui's Monaco-backed CodeEditor, which
// doesn't run in jsdom. We assert on the rendered `value` prop by shallowly
// intercepting `CodeEditor` and reading the string back.
jest.mock('@grafana/ui', () => {
  return {
    useStyles2: () => ({ wrapper: '' }),
    CodeEditor: ({ value }: { value: string }) => <pre data-testid="snippet">{value}</pre>,
  };
});

describe('ScrapeSnippet', () => {
  it('renders an Alloy prometheus.scrape block for the account', () => {
    const { getByTestId } = render(
      <ScrapeSnippet tuistUrl="https://tuist.dev" accountHandle="acme" scrapeInterval="15s" />
    );

    const snippet = getByTestId('snippet').textContent ?? '';

    expect(snippet).toContain('prometheus.scrape "tuist_acme"');
    expect(snippet).toContain('metrics_path    = "/api/accounts/acme/metrics"');
    expect(snippet).toContain('scrape_interval = "15s"');
    expect(snippet).toContain('__address__ = "tuist.dev:443"');
    expect(snippet).toContain('__scheme__  = "https"');
    expect(snippet).toContain('bearer_token    = sys.env("TUIST_METRICS_TOKEN")');
  });

  it('uses http and the explicit port for local development URLs', () => {
    const { getByTestId } = render(
      <ScrapeSnippet tuistUrl="http://localhost:8080" accountHandle="acme" scrapeInterval="30s" />
    );

    const snippet = getByTestId('snippet').textContent ?? '';

    expect(snippet).toContain('__address__ = "localhost:8080"');
    expect(snippet).toContain('__scheme__  = "http"');
    expect(snippet).toContain('scrape_interval = "30s"');
  });

  it('sanitises account handles that are not valid Alloy identifiers', () => {
    const { getByTestId } = render(
      <ScrapeSnippet tuistUrl="https://tuist.dev" accountHandle="Acme-Inc" scrapeInterval="15s" />
    );

    const snippet = getByTestId('snippet').textContent ?? '';

    expect(snippet).toContain('prometheus.scrape "tuist_acme_inc"');
    expect(snippet).toContain('metrics_path    = "/api/accounts/Acme-Inc/metrics"');
  });
});
