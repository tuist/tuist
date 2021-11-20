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
} from '@shopify/polaris';

const NewProject = () => {
  const [selected, setSelected] = useState('today');

  const handleSelectChange = useCallback(
    (value) => setSelected(value),
    [],
  );

  const options = [
    { label: 'Today', value: 'today' },
    { label: 'Yesterday', value: 'yesterday' },
    { label: 'Last 7 days', value: 'lastWeek' },
  ];

  return (
    <Page title="New Project">
      <Layout sectioned>
        <Card sectioned>
          <FormLayout>
            <Select
              label="Owner"
              options={options}
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
