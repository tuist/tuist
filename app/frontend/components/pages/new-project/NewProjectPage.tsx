import React, { useState, useCallback, useEffect } from 'react';
import {
  Card,
  FormLayout,
  TextField,
  Layout,
  Page,
  Select,
  Button,
  Stack,
  InlineError,
} from '@shopify/polaris';

import { useNavigate } from 'react-router-dom';
import { observer, useLocalObservable } from 'mobx-react-lite';
import { NewProjectPageStore } from './NewProjectPageStore';
import { useApolloClient } from '@apollo/client';

export const NewProjectPage = observer(() => {
  const client = useApolloClient();
  const newProjectPageStore = useLocalObservable(() => {
    const newProjectPageStore = new NewProjectPageStore(client);
    newProjectPageStore.load();
    return newProjectPageStore;
  });

  const navigate = useNavigate();
  const createProjectButtonTapped = () => {
    newProjectPageStore.createNewProject((projectSlug) =>
      navigate(`/${projectSlug}`),
    );
  };

  return (
    <Page title="New Project">
      <Layout sectioned>
        <Card sectioned>
          <FormLayout>
            <Select
              label="Owner"
              options={newProjectPageStore.options}
              onChange={(value) =>
                newProjectPageStore.selectedProjectOwnerChanged(value)
              }
              value={
                newProjectPageStore.selectedProjectOwner ?? undefined
              }
            />
            {newProjectPageStore.isCreatingOrganization && (
              <TextField
                type="text"
                label="Organization name"
                error={
                  newProjectPageStore.isOrganizationNameValid
                    ? false
                    : 'The name is invalid'
                }
                helpText="The allowed characters are a-z and the dash symbol '-' (for example organization-name)"
                value={newProjectPageStore.organizationName}
                onChange={(value) =>
                  newProjectPageStore.organizationNameChanged(value)
                }
                autoComplete="off"
              />
            )}
            <TextField
              type="text"
              label="Project name"
              error={
                newProjectPageStore.isNewProjectNameValid
                  ? false
                  : 'The name is invalid'
              }
              helpText="The allowed characters are a-z and the dash symbol '-' (for example project-name)"
              value={newProjectPageStore.newProjectName}
              onChange={(value) => {
                newProjectPageStore.projectNameChanged(value);
              }}
              autoComplete="off"
            />
            {newProjectPageStore.formErrors.map((error) => (
              <InlineError message={error} fieldID="" key={error} />
            ))}
            <Stack>
              <Button
                primary
                disabled={
                  newProjectPageStore.isCreateProjectButtonDisabled
                }
                onClick={createProjectButtonTapped}
              >
                Create project
              </Button>
              <Button
                destructive
                onClick={() => {
                  navigate(-1);
                }}
              >
                Cancel
              </Button>
            </Stack>
          </FormLayout>
        </Card>
      </Layout>
    </Page>
  );
});
