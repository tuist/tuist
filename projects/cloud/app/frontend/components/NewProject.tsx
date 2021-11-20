import React, { useState, useCallback, useEffect } from 'react';
import {
  Heading,
  TextContainer,
  Card,
  List,
  FormLayout,
  TextField,
  Layout,
  Page,
  Select,
  Button,
  SelectOption,
} from '@shopify/polaris';

import {
  Account,
  Project,
  useMyAccountsQuery,
} from '@/graphql/types';

const NewProject = () => {
  const myAccounts = useMyAccountsQuery().data?.accounts ?? [];
  const options: SelectOption[] = myAccounts.map((account) => {
    return {
      label: account.name,
      value: account.id,
    };
  });

  const [selectedProjectOwner, setSelectedProjectOwner] = useState<
    Account['id'] | undefined
  >(undefined);

  useEffect(() => {
    // Set default project owner as the first entry from the `myAccounts` array
    if (selectedProjectOwner === undefined) {
      setSelectedProjectOwner(myAccounts[0]?.id);
    }
  }, [myAccounts]);

  const handleSelectChange = useCallback(
    (value) => setSelectedProjectOwner(value),
    [],
  );

  const [projectName, setProjectName] = useState<Project['name']>('');
  const handleProjectNameChange = useCallback(
    (projectName) => setProjectName(projectName),
    [],
  );

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
            <TextField
              type="text"
              label="Project name"
              value={projectName}
              onChange={handleProjectNameChange}
            />
            <Button
              disabled={
                projectName.length === 0 ||
                selectedProjectOwner === undefined
              }
            >
              Create project
            </Button>
          </FormLayout>
        </Card>
      </Layout>
    </Page>
  );
};

export default NewProject;
