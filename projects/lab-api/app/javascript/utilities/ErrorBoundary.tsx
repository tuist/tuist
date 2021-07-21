import React from 'react';
import Bugsnag from '@bugsnag/js';

let BugsnagErrorBoundary;

if (ENVIRONMENT !== 'development') {
  BugsnagErrorBoundary =
    Bugsnag.getPlugin('react').createErrorBoundary(React);
}

const ErrorBoundary = ({
  children,
}: {
  children?: React.ReactNode;
}) => {
  if (ENVIRONMENT === 'development') {
    return <>{children}</>;
  }
  return <BugsnagErrorBoundary>{children}</BugsnagErrorBoundary>;
};

export default ErrorBoundary;
