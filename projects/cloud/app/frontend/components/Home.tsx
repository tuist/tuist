import React, { useState, useCallback, useEffect } from 'react';
import { useMeQuery, useProjectQuery } from '@/graphql/types';
import {
  useParams,
  useNavigate,
  useLocation,
  Outlet,
} from 'react-router-dom';
import {
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
  SkeletonBodyText,
  SkeletonDisplayText,
  SkeletonPage,
  Toast,
  TopBar,
  Button,
  Popover,
  ActionList,
  ActionListItemDescriptor,
  IconableAction,
  NavigationItemProps,
} from '@shopify/polaris';
import {
  StoreMajor,
  HomeMajor,
  PackageMajor,
  PlusMinor,
  SettingsMajor,
} from '@shopify/polaris-icons';
import { HomeStore, HomeStoreContext } from '@/stores/HomeStore';
import { observer } from 'mobx-react-lite';
import { useApolloClient } from '@apollo/client';
import csrfToken from '@/utilities/csrfToken';

const Home = observer(() => {
  const { projectName, accountName } = useParams();
  const navigate = useNavigate();
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

  const signOut = useCallback(() => {
    setIsLoading(true);
    fetch('/users/sign_out', {
      method: 'delete',
      headers: { 'X-CSRF-Token': csrfToken ?? '' },
    })
      .then(() => {
        window.location.assign('/user/sign_in');
      })
      .catch((error) => {
        setIsLoading(false);
        throw error;
      });
  }, [document, setIsLoading]);

  const userMenuActions: { items: IconableAction[] }[] = [
    {
      items: [{ content: 'Sign out', onAction: signOut }],
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
      avatar={user?.avatarUrl ?? ''}
      initials={user?.email[0] ?? ''}
      open={userMenuActive}
      onToggle={toggleUserMenuActive}
    />
  );

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

  const myProjects = useMeQuery();
  const myProjectsActions: ActionListItemDescriptor[] =
    myProjects.data?.me.projects.map(({ name, slug }) => {
      return {
        content: name,
        onAction: () => {
          navigate(`/${slug}`);
          toggleActive();
        },
      };
    }) ?? [];
  const contextControlMarkup = (
    <div style={{ marginTop: '9px', marginLeft: '12px' }}>
      <Popover
        active={active}
        activator={activator}
        onClose={toggleActive}
      >
        <ActionList
          items={myProjectsActions.concat([
            {
              content: 'Create new project',
              onAction: () => {
                navigate('/new');
                toggleActive();
              },
              icon: PlusMinor,
            },
          ])}
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

  const location = useLocation();
  let navigationItems: NavigationItemProps[] = [
    // TODO: Bring back once we have what to display on dashboard
    // {
    //   label: 'Dashboard',
    //   icon: HomeMajor,
    //   url: '',
    //   selected: location.pathname.endsWith(projectName ?? ''),
    // },
    {
      label: 'Remote Cache',
      icon: PackageMajor,
      url: 'remote-cache',
      selected:
        location.pathname.endsWith(projectName ?? '') ||
        location.pathname.endsWith('remote-cache'),
    },
  ];
  const project = useProjectQuery({
    variables: {
      name: projectName ?? '',
      accountName: accountName ?? '',
    },
  });

  if (
    project.data?.project?.account.owner.__typename === 'Organization'
  ) {
    navigationItems.push({
      label: 'Organization',
      icon: StoreMajor,
      url: 'organization',
      selected: location.pathname.endsWith('organization'),
    });
  }
  navigationItems.push({
    label: 'Settings',
    icon: SettingsMajor,
    url: 'settings',
    selected: location.pathname.endsWith('settings'),
  });

  const navigationMarkup = (
    <Navigation location="/">
      <Navigation.Section items={navigationItems} />
    </Navigation>
  );

  const loadingMarkup = isLoading ? <Loading /> : null;

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

  const pageMarkup = isLoading ? loadingPageMarkup : <Outlet />;

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

  const client = useApolloClient();
  const [homeStore] = useState(new HomeStore(client));

  useEffect(() => {
    if (!accountName || !projectName) {
      return;
    }
    homeStore.load(projectName, accountName);
  }, [accountName, projectName]);

  return (
    <HomeStoreContext.Provider value={homeStore}>
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
    </HomeStoreContext.Provider>
  );
});

export default Home;
