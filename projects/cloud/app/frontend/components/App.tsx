import React from 'react';
import GraphqlProvider from '@/networking/GraphqlProvider';
import ErrorBoundary from '@/components/boundaries/ErrorBoundary';
import '@shopify/polaris/dist/styles.css';
import {
  HashRouter,
  Routes,
  Route,
  useLocation,
  BrowserRouter,
  Link as ReactRouterLink,
  useNavigate,
} from 'react-router-dom';
import NoPageFound from './NoPageFound';
import NewProject from './NewProject';
import Dashboard from './Dashboard';
import Home from './Home';
import { useMeQuery } from '@/graphql/types';
import RemoteCache from './RemoteCache';
import Organization from './Organization';

import { AppProvider } from '@shopify/polaris';

const AppRoutes = () => {
  const location = useLocation();
  const navigate = useNavigate();

  const { data, loading, error } = useMeQuery();
  if (loading) {
    return <div>loading</div>;
  } else if (error) {
    return <div>{JSON.stringify(error)}</div>;
  } else {
    if (location.pathname == '/') {
      const lastVisitedProject = data?.me.lastVisitedProject;
      const projects = data?.me.projects ?? [];
      const navigateToProjectPath =
        lastVisitedProject?.slug ?? projects[0]?.slug;
      if (navigateToProjectPath) {
        navigate(`/${navigateToProjectPath}`);
      } else {
        navigate('/new');
      }
    }
    return (
      <Routes>
        <Route path="/:accountName/:projectName" element={<Home />}>
          <Route path="" element={<Dashboard />} />
          <Route path="remote-cache" element={<RemoteCache />} />
          <Route path="organization" element={<Organization />} />
        </Route>
        <Route path="/new" element={<NewProject />} />
        <Route element={<NoPageFound />} />
      </Routes>
    );
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
            linkComponent={Link}
          >
            <BrowserRouter>
              <AppRoutes />
            </BrowserRouter>
          </AppProvider>
        </div>
      </GraphqlProvider>
    </ErrorBoundary>
  );
};

/// Inspired by: https://github.com/Shopify/polaris-react/issues/2575#issuecomment-574269370
const Link = ({ url, children, className, ...rest }) => {
  return (
    <ReactRouterLink to={url} {...{ className }} {...rest}>
      {children}
    </ReactRouterLink>
  );
};

export default App;
