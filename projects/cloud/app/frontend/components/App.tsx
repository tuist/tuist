import React from 'react';
import GraphqlProvider from '@/networking/GraphqlProvider';
import ErrorBoundary from '@/components/boundaries/ErrorBoundary';
import '@shopify/polaris/dist/styles.css';
import {
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
import RemoteCachePage from './pages/remote-cache/RemoteCachePage';
import OrganizationPage from './pages/organization/OrganizationPage';

import TuistCloudAppProvider from './TuistCloudAppProvider';
import AcceptInvitationPage from './pages/invitations/AcceptInvitationPage';
import SettingsPage from './pages/settings/SettingsPage';

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
        <Route
          path="/invitations/:token"
          element={<AcceptInvitationPage />}
        />
        <Route path="/:accountName/:projectName" element={<Home />}>
          {/* TODO: Return dashboard here once we have what to display there */}
          <Route path="" element={<RemoteCachePage />} />
          <Route path="remote-cache" element={<RemoteCachePage />} />
          <Route path="organization" element={<OrganizationPage />} />
          <Route path="settings" element={<SettingsPage />} />
        </Route>
        <Route path="/new" element={<NewProject />} />
        <Route element={<NoPageFound />} />
      </Routes>
    );
  }
};

const App = (): JSX.Element => {
  return (
    <ErrorBoundary>
      <GraphqlProvider>
        <div style={{ height: '500px' }}>
          <TuistCloudAppProvider>
            <BrowserRouter>
              <AppRoutes />
            </BrowserRouter>
          </TuistCloudAppProvider>
        </div>
      </GraphqlProvider>
    </ErrorBoundary>
  );
};

export default App;
