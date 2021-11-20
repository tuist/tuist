import React from 'react';
import GraphqlProvider from '@/networking/GraphqlProvider';
import ErrorBoundary from '@/components/boundaries/ErrorBoundary';
import '@shopify/polaris/dist/styles.css';
import { BrowserRouter, Switch, Route } from 'react-router-dom';
import NoPageFound from './NoPageFound';
import NewProject from './NewProject';
import Dashboard from './Dashboard';

import { AppProvider } from '@shopify/polaris';

const Routes = () => {
  return (
    <Switch>
      <Route
        path="/:accountName/:projectName"
        component={Dashboard}
      />
      <Route path="/new" component={NewProject} />
      <Route component={NoPageFound} />
    </Switch>
  );
};

const App = (): JSX.Element => {
  const theme = {
    logo: {
      width: 124,
      topBarSource:
        'https://cdn.shopify.com/s/files/1/0446/6937/files/jaded-pixel-logo-color.svg?6215648040070010999',
      contextualSaveBarSource:
        'https://cdn.shopify.com/s/files/1/0446/6937/files/jaded-pixel-logo-gray.svg?6215648040070010999',
      url: 'http://jadedpixel.com',
      accessibilityLabel: 'Jaded Pixel',
    },
  };
  return (
    <ErrorBoundary>
      <GraphqlProvider>
        <div style={{ height: '500px' }}>
          <AppProvider
            theme={theme}
            i18n={{
              Polaris: {
                Avatar: {
                  label: 'Avatar',
                  labelWithInitials:
                    'Avatar with initials {initials}',
                },
                ContextualSaveBar: {
                  save: 'Save',
                  discard: 'Discard',
                },
                TextField: {
                  characterCount: '{count} characters',
                },
                TopBar: {
                  toggleMenuLabel: 'Toggle menu',
                },
                Modal: {
                  iFrameTitle: 'body markup',
                },
                Frame: {
                  skipToContent: 'Skip to content',
                  navigationLabel: 'Navigation',
                  Navigation: {
                    closeMobileNavigationLabel: 'Close navigation',
                  },
                },
              },
            }}
          >
            <BrowserRouter>
              <Routes />
            </BrowserRouter>
          </AppProvider>
        </div>
      </GraphqlProvider>
    </ErrorBoundary>
  );
};

export default App;
