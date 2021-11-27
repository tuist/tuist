import React from 'react';
import { Page } from '@shopify/polaris';
import { useParams } from 'react-router';

const Organization = () => {
  const { accountName: organizationName } = useParams();

  return (
    <Page title={organizationName}>
      <p>{organizationName}</p>
    </Page>
  );
};

export default Organization;
