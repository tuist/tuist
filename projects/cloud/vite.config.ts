import { defineConfig } from 'vite';
import RubyPlugin from 'vite-plugin-ruby';
import ReactRefreshPlugin from '@vitejs/plugin-react-refresh';
import EnvironmentPlugin from 'vite-plugin-environment';
import FullReloadPlugin from 'vite-plugin-full-reload';
import { BugsnagSourceMapUploaderPlugin } from 'vite-plugin-bugsnag';

let environment = process.env.RAILS_ENV;
if (!environment || environment === '') {
  environment = 'development';
}

const isDistEnv = environment === 'production';
const bugsnagFrontendKey = process.env.BUGSNAG_FRONTEND_API_KEY;

const bugsnagOptions = {
  apiKey: bugsnagFrontendKey,
  appVersion: process.env.APP_VERSION,
};

export default defineConfig({
  plugins: [
    RubyPlugin(),
    EnvironmentPlugin({
      BASE_URL: process.env.BASE_URL,
      BUGSNAG_FRONTEND_KEY: bugsnagFrontendKey ?? '',
      ENVIRONMENT: environment,
    }),
    FullReloadPlugin(['config/routes.rb', 'app/views/**/*'], {
      delay: 200,
    }),
    ReactRefreshPlugin(),
    isDistEnv &&
      BugsnagSourceMapUploaderPlugin({
        ...bugsnagOptions,
        overwrite: true,
      }),
  ],
});
