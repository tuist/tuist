import React, { useState, useCallback, useEffect } from 'react';
import {
  Card,
  FormLayout,
  TextField,
  Layout,
  Page,
  Select,
  Button,
  SelectOption,
  Stack,
} from '@shopify/polaris';

import {
  Account,
  Project,
  useCreateProjectMutation,
  useMyAccountsQuery,
} from '@/graphql/types';
import { useNavigate } from 'react-router-dom';

const NewProject = () => {
  const myAccounts = useMyAccountsQuery().data?.accounts ?? [];
  const options: SelectOption[] = myAccounts
    .map((account) => {
      return {
        label: account.name,
        value: account.id,
      };
    })
    .concat([
      {
        label: 'Create new organization',
        value: 'new',
      },
    ]);

  const [selectedProjectOwner, setSelectedProjectOwner] = useState<
    Account['id'] | undefined
  >(undefined);

  const [isCreatingOrganization, setIsCreatingOrganization] =
    useState(false);

  useEffect(() => {
    // Set default project owner as the first entry from the `myAccounts` array
    if (
      selectedProjectOwner === undefined &&
      !isCreatingOrganization
    ) {
      setSelectedProjectOwner(myAccounts[0]?.id);
    }
  }, [myAccounts]);

  const handleSelectChange = useCallback((value) => {
    if (value === 'new') {
      setIsCreatingOrganization(true);
    } else {
      setIsCreatingOrganization(false);
    }
    setSelectedProjectOwner(value);
  }, []);

  const [projectName, setProjectName] = useState<Project['name']>('');
  const handleProjectNameChange = useCallback(
    (projectName) => setProjectName(projectName),
    [],
  );

  const [organizationName, setOrganizationName] =
    useState<Account['name']>('');
  const handleOrganizationNameChange = useCallback(
    (organizationName) => setOrganizationName(organizationName),
    [],
  );

  const navigate = useNavigate();
  const [createProject] = useCreateProjectMutation({
    onCompleted: ({ createProject }) => {
      navigate(`/${createProject.slug}`);
    },
  });

  const isCreateProjectButtonDisabled =
    projectName.length === 0 ||
    selectedProjectOwner === undefined ||
    (isCreatingOrganization && organizationName.length === 0);

  const handleCreateProjectButtonTapped = useCallback(() => {
    createProject({
      variables: {
        input: {
          accountId: isCreatingOrganization
            ? null
            : selectedProjectOwner!,
          name: projectName,
          organizationName: isCreatingOrganization
            ? organizationName
            : null,
        },
      },
    });
  }, [
    isCreatingOrganization,
    selectedProjectOwner,
    organizationName,
    projectName,
  ]);

  return (
    <Page title="New Project">
      <Layout sectioned>
        <Card sectioned>
          <FormLayout>
            <Select
              label="Owner"
              options={options}
              onChange={handleSelectChange}
              value={selectedProjectOwner}
            />
            {isCreatingOrganization && (
              <TextField
                type="text"
                label="Organization name"
                value={organizationName}
                onChange={handleOrganizationNameChange}
              />
            )}
            {/* TODO: Only allow kebab-case names */}
            <TextField
              type="text"
              label="Project name"
              value={projectName}
              onChange={handleProjectNameChange}
            />
            <Stack>
              <Button
                primary
                disabled={isCreateProjectButtonDisabled}
                onClick={handleCreateProjectButtonTapped}
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
};

export default NewProject;
