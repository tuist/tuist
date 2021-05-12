import * as React from "react";
import Bugsnag from "@bugsnag/js";
import BugsnagPluginReact from "@bugsnag/plugin-react";

// @ts-ignore
const bugsnagKey = process.env.BUGSNAG_FRONTEND_KEY;

type Props = {
  children?: React.ReactNode;
};

const ErrorTracking = ({ children }: Props): React.ReactNode => {
  let ErrorBoundary;
  if (bugsnagKey) {
    console.log(bugsnagKey);
    Bugsnag.start({
      // @ts-ignore
      apiKey: bugsnagKey,
      plugins: [new BugsnagPluginReact()],
    });
    ErrorBoundary = Bugsnag.getPlugin("react").createErrorBoundary(React);
    return <ErrorBoundary>{children}</ErrorBoundary>;
  } else {
    return children;
  }
};

export default ErrorTracking;
