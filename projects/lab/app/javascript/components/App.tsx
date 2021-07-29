import React from 'react';
import {
  BrowserRouter as Router,
  Switch,
  Route,
} from 'react-router-dom';
import { AppProvider } from '@shopify/polaris';
import ClientProvider from '../networking/ClientProvider';
import RESTClientProvider from '../networking/RESTClientProvider';

import ErrorBoundary from '../utilities/ErrorBoundary';
import HomePage from '../pages/HomePage';
import ProjectNewPage from '../pages/ProjectNewPage';
import OrganizationNewPage from '../pages/OrganizationNewPage';
import SettingsPage from '../pages/SettingsPage';
import {
  projectNewPath,
  organizationNewPath,
  settingsPath,
} from '../utilities/routes';
import EnvironmentProvider from '../utilities/EnvironmentProvider';
import theme from '../polaris/theme';

export default function App() {
  return (
    <ErrorBoundary>
      <RESTClientProvider>
        <ClientProvider>
          <AppProvider theme={theme} i18n={{}}>
            <EnvironmentProvider>
              <Router>
                <Switch>
                  <Route path="/" component={HomePage} exact />
                  <Route
                    path={projectNewPath}
                    component={ProjectNewPage}
                  />
                  <Route
                    path={organizationNewPath}
                    component={OrganizationNewPage}
                  />
                  <Route
                    path={settingsPath}
                    component={SettingsPage}
                  />
                </Switch>
              </Router>
            </EnvironmentProvider>
          </AppProvider>
        </ClientProvider>
      </RESTClientProvider>
    </ErrorBoundary>
  );
}
