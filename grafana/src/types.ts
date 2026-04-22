export interface TuistAppJsonData {
  /** The Tuist server URL, e.g. https://tuist.dev or https://staging.tuist.dev. */
  tuistUrl?: string;
  /** The account handle (user or organisation) whose metrics should be scraped. */
  accountHandle?: string;
  /** Scrape interval, e.g. "15s", "30s". */
  scrapeInterval?: string;
}

export interface TuistAppSecureJsonData {
  /** Bearer account token carrying the `account:metrics:read` scope. */
  metricsToken?: string;
}

export interface TuistAppSecureJsonFields {
  metricsToken?: boolean;
}
