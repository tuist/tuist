import React from 'react';
import Bugsnag from '@bugsnag/js';
import BugsnagPluginReact from '@bugsnag/plugin-react';
import { bugsnagFrontendKey, environment } from '@/shared/constants';
import { Environment } from '@/shared/Environment';

let BugsnagErrorBounday: any;

if (environment === Environment.Production) {
  Bugsnag.start({
    apiKey: bugsnagFrontendKey,
    plugins: [new BugsnagPluginReact()],
  });
  BugsnagErrorBounday = // @ts-ignore
    Bugsnag.getPlugin('react').createErrorBoundary(React);
}

interface ErrorBoundaryProps {
  children?: React.ReactNode;
}

const ErrorBoundary = ({ children }: ErrorBoundaryProps) => {
  if (environment === Environment.Production) {
    return <BugsnagErrorBounday>{children}</BugsnagErrorBounday>;
  } else {
    return <>{children}</>;
  }
};

export default ErrorBoundary;
