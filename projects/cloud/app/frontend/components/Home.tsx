import React, { useState, useCallback } from 'react';
import { useMeQuery, useMyProjectsQuery } from '@/graphql/types';
import { useParams, useNavigate, Outlet } from 'react-router-dom';
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
} from '@shopify/polaris';
import {
  ConversationMinor,
  HomeMajor,
  PackageMajor,
  PlusMinor,
} from '@shopify/polaris-icons';

const Home = () => {
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

  const goToOrganizations = useCallback(() => {
    navigate('/organizations');
  }, []);

  const userMenuActions: { items: IconableAction[] }[] = [
    {
      items: [
        { content: 'Organizations', onAction: goToOrganizations },
      ],
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
  const myProjectsActions: ActionListItemDescriptor[] =
    myProjects.data?.projects.map(({ name }) => {
      return {
        content: name,
        onAction: () => {
          navigate(`/${accountName}/${name}`);
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

  const navigationMarkup = (
    <Navigation location="/">
      <Navigation.Section
        items={[
          {
            label: 'Dashboard',
            icon: HomeMajor,
            url: `/${accountName}/${projectName}`,
          },
          {
            label: 'Remote Cache',
            icon: PackageMajor,
            url: `/${accountName}/${projectName}/remote-cache`,
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

  const actualPageMarkup = <Outlet />;

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
  );
};

export default Home;
