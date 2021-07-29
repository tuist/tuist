/* eslint-disable */
const { environment } = require('@rails/webpacker');
const webpack = require('webpack');
/* eslint-enable */

let ENVIRONMENT = process.env.NODE_ENV;
if (!ENVIRONMENT) {
  ENVIRONMENT = 'development';
}

environment.plugins.append(
  'DefinePlugin',
  new webpack.DefinePlugin({
    BASE_URL: JSON.stringify(process.env.BASE_URL),
    BUGSNAG_FRONTEND_API_KEY: JSON.stringify(
      process.env.BUGSNAG_FRONTEND_API_KEY,
    ),
    ENVIRONMENT: JSON.stringify(ENVIRONMENT),
  }),
);

module.exports = environment;
