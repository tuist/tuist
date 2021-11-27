import React from 'react';
import {
  Page,
  Card,
  ResourceList,
  Avatar,
  ResourceItem,
  TextStyle,
  Stack,
} from '@shopify/polaris';
import { useParams } from 'react-router';
import { useOrganizationQuery } from '@/graphql/types';

interface User {
  email: string;
  name: string;
  avatarUrl: string | undefined;
}

const UserItem = ({ user }: { user: User }) => {
  return (
    <div style={{ padding: '10px 100px 10px 20px' }}>
      <Stack>
        <Avatar customer size="medium" source={user.avatarUrl} />
        <Stack vertical={true} spacing={'none'}>
          <TextStyle variation="strong">{user.name}</TextStyle>
          <TextStyle variation="subdued">{user.email}</TextStyle>
        </Stack>
      </Stack>
    </div>
  );
};

const Organization = () => {
  const { accountName: organizationName } = useParams();

  const organization = useOrganizationQuery({
    variables: { name: organizationName ?? '' },
  }).data?.organization;

  return (
    <Page title={organizationName}>
      <Card title="Users">
        <ResourceList
          resourceName={{ singular: 'customer', plural: 'customers' }}
          items={
            organization?.users.map((user) => {
              return {
                email: user.email,
                name: user.account.name,
                avatarUrl: user.avatarUrl ?? undefined,
              };
            }) ?? []
          }
          renderItem={(item) => {
            const { email, name, avatarUrl } = item;

            return <UserItem user={item} />;
          }}
        />
      </Card>
    </Page>
  );
};

export default Organization;
