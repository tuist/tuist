import React from 'react';
import {
  Card,
  FormLayout,
  Frame,
  Layout,
  Page,
  TopBar,
  TextField,
  Form,
  Button,
} from '@shopify/polaris';
import { Helmet } from 'react-helmet';
import { useForm, Controller } from 'react-hook-form';
import TopBarUserMenu from '../polaris/TopBarUserMenu';
// import { useOrganizationCreateMutation } from '../graphql/types';

type FormData = {
  name: string;
};

const OrganizationNewPage = () => {
  // const [
  //   createOrganization,
  //   { error: createOrganizationError, data: createOrganizationData },
  // ] = useOrganizationCreateMutation();

  const {
    control,
    formState: { errors },
    handleSubmit,
  } = useForm<FormData>();
  const onSubmit = () => {
    // createOrganization({
    //   variables: { organization: { name: data.name } },
    // });
  };

  // Page Markup
  const pageMarkup = (
    <Page title="Create a new organization">
      <Layout>
        <Layout.AnnotatedSection
          title="Organization details"
          description="We'll need some basic information from your organization in order to create it."
        >
          <Card sectioned>
            <Form noValidate onSubmit={handleSubmit(onSubmit)}>
              <FormLayout>
                <Controller
                  name="name"
                  control={control}
                  defaultValue=""
                  rules={{ required: true }}
                  render={({ field }) => (
                    <TextField
                      label="Organization name"
                      placeholder="Example: craftweg"
                      onChange={field.onChange}
                      value={field.value}
                      error={
                        errors.name?.type === 'required'
                          ? 'The name is required to create an organization.'
                          : null
                      }
                    />
                  )}
                />

                <Button primary submit>
                  Submit
                </Button>
              </FormLayout>
            </Form>
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
        <title>New organization</title>
      </Helmet>
      <Frame topBar={topBarMarkup}>{pageMarkup}</Frame>
    </div>
  );
};

export default OrganizationNewPage;
