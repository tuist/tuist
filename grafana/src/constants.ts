import pluginJson from './plugin.json';

export const PLUGIN_ID = pluginJson.id;
export const PLUGIN_NAME = pluginJson.name;

export const ROUTES = {
  Setup: 'setup',
} as const;

export const DEFAULT_TUIST_URL = 'https://tuist.dev';
export const DEFAULT_SCRAPE_INTERVAL = '15s';
export const REQUIRED_SCOPE = 'account:metrics:read';
