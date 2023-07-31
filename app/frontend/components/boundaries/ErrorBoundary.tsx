import React from 'react';
import { environment } from '@/shared/constants';
import { Environment } from '@/shared/Environment';
import { appsignal } from './appsignal.js';
import { ErrorBoundary as AppSignalErrorBoundary } from '@appsignal/react';

interface ErrorBoundaryProps {
  children?: React.ReactNode;
}

const ErrorBoundary = ({ children }: ErrorBoundaryProps) => {
  if (environment === Environment.Production) {
    return (
      // @ts-ignore
      <AppSignalErrorBoundary instance={appsignal}>
        {children}
      </AppSignalErrorBoundary>
    );
  } else {
    return <>{children}</>;
  }
};

export default ErrorBoundary;
