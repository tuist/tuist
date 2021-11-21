import React, { useCallback, useState } from 'react';
import GraphqlProvider from '@/networking/GraphqlProvider';
import ErrorBoundary from '@/components/boundaries/ErrorBoundary';
import '@shopify/polaris/dist/styles.css';
import { useMeQuery, useMyProjectsQuery } from '@/graphql/types';
import { BrowserRouter, Switch, Route } from 'react-router-dom';

import {
  AppProvider,
  Heading,
  Card,
  TextField,
  TextContainer,
  ContextualSaveBar,
  FormLayout,
  Modal,
  Frame,
  Layout,
  Loading,
  Navigation,
  Page,
  SkeletonBodyText,
  SkeletonDisplayText,
  SkeletonPage,
  Toast,
  TopBar,
  Button,
  Popover,
  ActionList,
  isNavigationItemActive,
} from '@shopify/polaris';
import {
  ConversationMinor,
  HomeMajor,
  PackageMajor,
} from '@shopify/polaris-icons';

const FrameExample = ({ match, history }) => {
  const {
    params: { projectName, accountName },
  } = match;
  const [toastActive, setToastActive] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [isDirty, setIsDirty] = useState(false);
  const [userMenuActive, setUserMenuActive] = useState(false);
  const [mobileNavigationActive, setMobileNavigationActive] =
    useState(false);
  const [modalActive, setModalActive] = useState(false);
  const [supportSubject, setSupportSubject] = useState('');
  const [supportMessage, setSupportMessage] = useState('');

  const handleSubjectChange = useCallback(
    (value) => setSupportSubject(value),
    [],
  );
  const handleMessageChange = useCallback(
    (value) => setSupportMessage(value),
    [],
  );
  const handleDiscard = useCallback(() => {
    setIsDirty(false);
  }, []);
  const handleSave = useCallback(() => {
    setIsDirty(false);
    setToastActive(true);
  }, []);
  const toggleToastActive = useCallback(
    () => setToastActive((toastActive) => !toastActive),
    [],
  );
  const toggleUserMenuActive = useCallback(
    () => setUserMenuActive((userMenuActive) => !userMenuActive),
    [],
  );
  const toggleMobileNavigationActive = useCallback(
    () =>
      setMobileNavigationActive(
        (mobileNavigationActive) => !mobileNavigationActive,
      ),
    [],
  );
  const toggleModalActive = useCallback(
    () => setModalActive((modalActive) => !modalActive),
    [],
  );

  const toastMarkup = toastActive ? (
    <Toast onDismiss={toggleToastActive} content="Changes saved" />
  ) : null;

  const userMenuActions = [
    {
      items: [{ content: 'Community forums' }],
    },
  ];

  const contextualSaveBarMarkup = isDirty ? (
    <ContextualSaveBar
      message="Unsaved changes"
      saveAction={{
        onAction: handleSave,
      }}
      discardAction={{
        onAction: handleDiscard,
      }}
    />
  ) : null;

  const user = useMeQuery().data?.me;

  const userMenuMarkup = (
    <TopBar.UserMenu
      actions={userMenuActions}
      name={user?.email ?? ''}
      // TODO: Name from github
      detail="Name from Github"
      avatar={user?.avatarUrl ?? ''}
      // TODO: Initials
      initials="initials"
      open={userMenuActive}
      onToggle={toggleUserMenuActive}
    />
  );

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

  const [active, setActive] = useState(false);

  const toggleActive = useCallback(
    () => setActive((active) => !active),
    [],
  );

  const activator = (
    <Button onClick={toggleActive} disclosure>
      {projectName}
    </Button>
  );

  const myProjects = useMyProjectsQuery();
  const contextControlMarkup = (
    <div style={{ marginTop: '9px', marginLeft: '12px' }}>
      <Popover
        active={active}
        activator={activator}
        onClose={toggleActive}
      >
        {/* TODO: Add actions */}
        <ActionList
          items={myProjects.data?.projects.map(({ name }) => {
            return {
              content: name,
              onAction: () => {
                history.push(`/${accountName}/${name}`);
                toggleActive();
              },
            };
          })}
        />
      </Popover>
    </div>
  );

  const topBarMarkup = (
    <TopBar
      showNavigationToggle
      userMenu={userMenuMarkup}
      contextControl={contextControlMarkup}
      onNavigationToggle={toggleMobileNavigationActive}
    />
  );

  const navigationMarkup = (
    <Navigation location="/">
      <Navigation.Section
        items={[
          {
            label: 'Dashboard',
            icon: HomeMajor,
            url: '/dashboard',
          },
          {
            label: 'Remote Cache',
            icon: PackageMajor,
            url: '/remote-cache',
          },
        ]}
        action={{
          icon: ConversationMinor,
          accessibilityLabel: 'Contact support',
          onClick: toggleModalActive,
        }}
      />
    </Navigation>
  );

  const loadingMarkup = isLoading ? <Loading /> : null;

  const actualPageMarkup = (
    <Switch>
      <Route path="/dashboard">
        <Page title="Account">
          <Layout>
            <Layout.AnnotatedSection
              title="Account details"
              description="Tuist Cloud will use this as your account information."
            >
              <Card sectioned>
                <TextContainer>
                  <Heading>Email</Heading>
                  <p>{user?.email}</p>
                </TextContainer>
              </Card>
            </Layout.AnnotatedSection>
          </Layout>
        </Page>
      </Route>
      <Route path="/remote-cache">
        <Page title="Remote Cache">
          <RemoteCache />
        </Page>
      </Route>
    </Switch>
  );

  const loadingPageMarkup = (
    <SkeletonPage>
      <Layout>
        <Layout.Section>
          <Card sectioned>
            <TextContainer>
              <SkeletonDisplayText size="small" />
              <SkeletonBodyText lines={9} />
            </TextContainer>
          </Card>
        </Layout.Section>
      </Layout>
    </SkeletonPage>
  );

  const pageMarkup = isLoading ? loadingPageMarkup : actualPageMarkup;

  const modalMarkup = (
    <Modal
      open={modalActive}
      onClose={toggleModalActive}
      title="Contact support"
      primaryAction={{
        content: 'Send',
        onAction: toggleModalActive,
      }}
    >
      <Modal.Section>
        <FormLayout>
          <TextField
            label="Subject"
            value={supportSubject}
            onChange={handleSubjectChange}
          />
          <TextField
            label="Message"
            value={supportMessage}
            onChange={handleMessageChange}
            multiline
          />
        </FormLayout>
      </Modal.Section>
    </Modal>
  );

  return (
    <div style={{ height: '500px' }}>
      <AppProvider
        theme={theme}
        i18n={{
          Polaris: {
            Avatar: {
              label: 'Avatar',
              labelWithInitials: 'Avatar with initials {initials}',
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
        <Frame
          topBar={topBarMarkup}
          navigation={navigationMarkup}
          showMobileNavigation={mobileNavigationActive}
          onNavigationDismiss={toggleMobileNavigationActive}
        >
          {contextualSaveBarMarkup}
          {loadingMarkup}
          {pageMarkup}
          {toastMarkup}
          {modalMarkup}
        </Frame>
      </AppProvider>
    </div>
  );
};

const RemoteCache = () => {
  return <p>My Remote Cache</p>;
};

const NoPageFound = () => {
  return <p>Page not found</p>;
};

const Routes = () => {
  return (
    <Switch>
      <Route
        path="/:accountName/:projectName"
        component={FrameExample}
      ></Route>
      <Route component={NoPageFound} />
    </Switch>
  );
};

const App = (): JSX.Element => {
  return (
    <ErrorBoundary>
      <GraphqlProvider>
        <BrowserRouter>
          <Routes />
        </BrowserRouter>
      </GraphqlProvider>
    </ErrorBoundary>
  );
};

export default App;
