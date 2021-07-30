const {
  BugsnagSourceMapUploaderPlugin,
  BugsnagBuildReporterPlugin,
} = require("webpack-bugsnag-plugins");

process.env.NODE_ENV = process.env.NODE_ENV || "production";

const environment = require("./environment");
const bugsnagApiKey = "4b8674da082f9f4f779936212d6d60d8";

if (!process.env.CI) {
  environment.plugins.append(
    "BugsnagBuildReporterPlugin",
    new BugsnagBuildReporterPlugin({
      apiKey: bugsnagApiKey,
    })
  );

  environment.plugins.append(
    "BugsnagSourceMapUploaderPlugin",
    new BugsnagSourceMapUploaderPlugin({
      apiKey: bugsnagApiKey,
      overwrite: true,
    })
  );
}

module.exports = environment.toWebpackConfig();
