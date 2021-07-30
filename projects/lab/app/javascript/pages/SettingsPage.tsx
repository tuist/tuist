import React, { useCallback, useState } from 'react';
import {
  Card,
  FormLayout,
  Frame,
  Layout,
  Page,
  Toast,
  TopBar,
} from '@shopify/polaris';
import { Helmet } from 'react-helmet';
import TopBarUserMenu from '../polaris/TopBarUserMenu';

const SettingsPage = () => {
  // Toast
  const [toastActive, setToastActive] = useState(false);
  const toggleToastActive = useCallback(
    () => setToastActive((_toastActive) => !_toastActive),
    [],
  );
  const toastMarkup = toastActive ? (
    <Toast onDismiss={toggleToastActive} content="Changes saved" />
  ) : null;

  // Page Markup
  const pageMarkup = (
    <Page title="Create a project">
      <Layout>
        <Layout.AnnotatedSection
          title="Project details"
          description="We'll need some basic information from your project in order to create it."
        >
          <Card sectioned>
            <FormLayout />
          </Card>
        </Layout.AnnotatedSection>
      </Layout>
    </Page>
  );

  const topBarUserMenu = <TopBarUserMenu />;
  const topBarMarkup = (
    <TopBar showNavigationToggle userMenu={topBarUserMenu} />
  );

  return (
    <div>
      <Helmet>
        <title>Settings</title>
      </Helmet>
      <Frame topBar={topBarMarkup}>
        {pageMarkup}
        {toastMarkup}
      </Frame>
    </div>
  );
};

export default SettingsPage;
