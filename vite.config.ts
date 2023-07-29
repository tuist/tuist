import { defineConfig } from 'vite';
import RubyPlugin from 'vite-plugin-ruby';
import ReactRefreshPlugin from '@vitejs/plugin-react-refresh';
import EnvironmentPlugin from 'vite-plugin-environment';
import FullReloadPlugin from 'vite-plugin-full-reload';

let environment = process.env.RAILS_ENV;
if (!environment || environment === '') {
  environment = 'development';
}

// const isDistEnv = environment === 'production';

// const bugsnagOptions = {
//   appVersion: process.env.APP_VERSION,
// };

export default defineConfig({
  plugins: [
    RubyPlugin(),
    EnvironmentPlugin({
      BASE_URL: process.env.BASE_URL,
      ENVIRONMENT: environment,
    }),
    FullReloadPlugin(['config/routes.rb', 'app/views/**/*'], {
      delay: 200,
    }),
    ReactRefreshPlugin(),
    // isDistEnv &&
    //   BugsnagSourceMapUploaderPlugin({
    //     ...bugsnagOptions,
    //     overwrite: true,
    //   }),
  ],
});
