import React from 'react';
import GraphqlProvider from '@/networking/GraphqlProvider';
import ErrorBoundary from '@/components/boundaries/ErrorBoundary';
import '@shopify/polaris/dist/styles.css';
import { BrowserRouter, Switch, Route, useHistory, useLocation } from 'react-router-dom';
import NoPageFound from './NoPageFound';
import NewProject from './NewProject';
import Dashboard from './Dashboard';
import { useMeQuery } from '@/graphql/types';

import { AppProvider } from '@shopify/polaris';

const Routes = () => {
  const location = useLocation();
  const history = useHistory();

  const {data, loading, error} = useMeQuery();
  if (loading) {
    return <div>loading</div>
  } else if (error) {
    return <div>{JSON.stringify(error)}</div>
  } else {
    if (location.pathname == "/") {
      const lastVisitedProject = data?.me.lastVisitedProject
      const projects = data?.me.projects ?? []
      const navigateToProjectPath = lastVisitedProject?.slug ?? projects[0]?.slug
      if (navigateToProjectPath) {
        history.push(`/${navigateToProjectPath}`);
      } else {
        history.push("/new");
      }
    }
    return <Switch>
      <Route
        path="/:accountName/:projectName"
        component={Dashboard}
      />
      <Route path="/new" component={NewProject} />
      <Route component={NoPageFound} />
    </Switch>
  }
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
