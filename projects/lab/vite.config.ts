import { defineConfig } from "vite";
import fs from "fs";
import path from "path";
import RubyPlugin from "vite-plugin-ruby";
import FullReload from "vite-plugin-full-reload";
import ViteReact from "@vitejs/plugin-react-refresh";
import ViteLegacy from "@vitejs/plugin-legacy";
import {
  BugsnagBuildReporterPlugin,
  BugsnagSourceMapUploaderPlugin,
} from "vite-plugin-bugsnag";
const version = "0.1.0";
const isDistEnv = process.env.RAILS_ENV === "production";

const bugsnagOptions = {
  apiKey: process.env.BUGSNAG_API_KEY,
  appVersion: version,
};

export default defineConfig({
  define: {
    "process.env.BUGSNAG_FRONTEND_KEY": JSON.stringify(
      process.env.BUGSNAG_FRONTEND_KEY
    ),
  },
  plugins: [
    RubyPlugin(),
    FullReload(["config/routes.rb", "app/views/**/*"], { delay: 200 }),
    ViteReact(),
    ViteLegacy({
      targets: ["defaults", "not IE 11"],
    }),
    isDistEnv &&
      BugsnagBuildReporterPlugin({
        ...bugsnagOptions,
        releaseStage: process.env.RAILS_ENV,
      }),
    isDistEnv &&
      BugsnagSourceMapUploaderPlugin({ ...bugsnagOptions, overwrite: true }),
  ],
});
