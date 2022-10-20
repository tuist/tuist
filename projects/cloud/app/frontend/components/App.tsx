import React from 'react';
import GraphqlProvider from '@/networking/GraphqlProvider';
import ErrorBoundary from '@/components/boundaries/ErrorBoundary';
import '@shopify/polaris/build/esm/styles.css';
import '@shopify/polaris-viz/build/esm/styles.css';
import {
  Routes,
  Route,
  useLocation,
  BrowserRouter,
  useNavigate,
} from 'react-router-dom';
import NoPageFound from './NoPageFound';
import { NewProjectPage } from './pages/new-project/NewProjectPage';
import DashboardPage from './pages/dashboard/DashboardPage';
import CommandEventDetailPage from './pages/commandEventDetail/CommandEventDetailPage';
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
          <Route path="" element={<DashboardPage />} />
          <Route path="remote-cache" element={<RemoteCachePage />} />
          <Route path="organization" element={<OrganizationPage />} />
          <Route path="settings" element={<SettingsPage />} />
          <Route
            path="command_event/:commandEventId"
            element={<CommandEventDetailPage />}
          />
        </Route>
        <Route path="/new" element={<NewProjectPage />} />
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
