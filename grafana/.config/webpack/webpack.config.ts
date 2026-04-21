// Thin wrapper around the webpack configuration shipped by
// `@grafana/create-plugin`. Keeping the wrapper (instead of a vendored copy)
// means we can pull in upstream config fixes with:
//
//   npx @grafana/create-plugin@latest update
//
// Any plugin-specific overrides (aliases, extra copy rules, Cypress fixtures)
// should go in this file so the upstream update doesn't clobber them.

import type { Configuration } from 'webpack';
import { getWebpackConfig } from '@grafana/create-plugin/webpack/webpack.config';

const config = async (env: Record<string, unknown>): Promise<Configuration> => {
  const baseConfig = await getWebpackConfig(env);
  return baseConfig;
};

export default config;
