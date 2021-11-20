import React, { useState, useCallback } from 'react';
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

import { useMyOrganizationsQuery } from '@/graphql/types';

const NewProject = () => {
  const [selected, setSelected] = useState('today');

  const handleSelectChange = useCallback(
    (value) => setSelected(value),
    [],
  );

  const organizationOptions: SelectOption[] =
    useMyOrganizationsQuery().data?.organizations.map(
      (organization) => {
        return {
          label: organization.name,
          value: organization.id,
        };
      },
    ) ?? [];

  return (
    <Page title="New Project">
      <Layout sectioned>
        <Card sectioned>
          <FormLayout>
            <Select
              label="Owner"
              options={organizationOptions}
              onChange={handleSelectChange}
              value={selected}
            />
            <TextField
              type="email"
              label="Project name"
              onChange={() => {}}
              autoComplete="email"
            />
            <Button>Create project</Button>
          </FormLayout>
        </Card>
      </Layout>
    </Page>
  );
};

export default NewProject;
