import React, { useCallback, useState } from 'react';
import {
  Page,
  Card,
  ResourceList,
  Avatar,
  TextStyle,
  Stack,
  ActionList,
  Popover,
  Button,
} from '@shopify/polaris';
import { useParams } from 'react-router';
import { useOrganizationQuery } from '@/graphql/types';

enum Role {
  admin = 'Admin',
  user = 'User',
}

interface User {
  email: string;
  name: string;
  avatarUrl: string | undefined;
  role: Role;
}

const UserRolePopover = ({ user }: { user: User }) => {
  // TODO: Enable actually changing the role
  const [isRolePopoverActive, setRolePopoverActive] = useState(false);
  const toggleRolePopoverActive = useCallback(
    () => setRolePopoverActive((active) => !active),
    [],
  );
  return (
    <div style={{ width: 100 }}>
      <Popover
        active={isRolePopoverActive}
        activator={
          <Button disclosure onClick={toggleRolePopoverActive}>
            {user.role}
          </Button>
        }
        onClose={toggleRolePopoverActive}
      >
        <ActionList
          items={[
            {
              content: 'Admin',
            },
            {
              content: 'User',
            },
          ]}
        />
      </Popover>
    </div>
  );
};

const UserItem = ({ user }: { user: User }) => {
  return (
    <div style={{ padding: '10px 100px 10px 20px' }}>
      <Stack alignment={'center'}>
        <Avatar customer size="medium" source={user.avatarUrl} />
        <Stack.Item fill={true}>
          <Stack vertical={true} spacing={'none'}>
            <TextStyle variation="strong">{user.name}</TextStyle>
            <TextStyle variation="subdued">{user.email}</TextStyle>
          </Stack>
        </Stack.Item>
        <UserRolePopover user={user} />
      </Stack>
    </div>
  );
};

const Organization = () => {
  const { accountName: organizationName } = useParams();

  const organization = useOrganizationQuery({
    variables: { name: organizationName ?? '' },
  }).data?.organization;

  const users =
    organization?.users.map((user) => {
      return {
        email: user.email,
        name: user.account.name,
        avatarUrl: user.avatarUrl ?? undefined,
        role: Role.user,
      };
    }) ?? [];

  const admins =
    organization?.admins.map((user) => {
      return {
        email: user.email,
        name: user.account.name,
        avatarUrl: user.avatarUrl ?? undefined,
        role: Role.admin,
      };
    }) ?? [];
  return (
    <Page title={organizationName}>
      <Card title="Users">
        <ResourceList
          resourceName={{ singular: 'customer', plural: 'customers' }}
          items={users
            .concat(admins)
            .sort(
              (first, second) =>
                0 - (first.name > second.name ? -1 : 1),
            )}
          renderItem={(item) => {
            return <UserItem user={item} />;
          }}
        />
      </Card>
    </Page>
  );
};

export default Organization;
