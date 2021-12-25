import React, { useCallback, useState, useContext } from 'react';
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
import { Role, Organization as _ } from '@/graphql/types';
import { observer } from 'mobx-react-lite';
import { HomeStoreContext } from '@/stores/HomeStore';

interface User {
  id: string;
  email: string;
  name: string;
  avatarUrl: string | undefined;
  role: Role;
}

const UserRolePopover = observer(({ user }: { user: User }) => {
  const { organizationStore } = useContext(HomeStoreContext);
  const [isRolePopoverActive, setRolePopoverActive] = useState(false);
  const toggleRolePopoverActive = useCallback(
    () => setRolePopoverActive((active) => !active),
    [],
  );

  const changeRole = useCallback(
    async ({ newRole }: { newRole: Role }) => {
      await organizationStore.changeUserRole(user.id, newRole);
      toggleRolePopoverActive();
    },
    [],
  );

  return (
    <div style={{ width: 100 }}>
      <Popover
        active={isRolePopoverActive}
        activator={
          <Button disclosure onClick={toggleRolePopoverActive}>
            {user.role.charAt(0).toUpperCase() + user.role.slice(1)}
          </Button>
        }
        onClose={toggleRolePopoverActive}
      >
        <ActionList
          items={[
            {
              content: 'Admin',
              onAction: () => {
                changeRole({ newRole: Role.Admin });
              },
            },
            {
              content: 'User',
              onAction: () => {
                changeRole({ newRole: Role.User });
              },
            },
          ]}
        />
      </Popover>
    </div>
  );
});

const UserItem = ({
  user,
  isAdmin,
}: {
  user: User;
  isAdmin: boolean;
}) => {
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
        {isAdmin ? (
          <UserRolePopover user={user} />
        ) : (
          <TextStyle>
            {user.role.charAt(0).toUpperCase() + user.role.slice(1)}
          </TextStyle>
        )}
      </Stack>
    </div>
  );
};

const Organization = observer(() => {
  const { accountName: organizationName } = useParams();
  const { organizationStore, userStore } =
    useContext(HomeStoreContext);
  const isAdmin =
    (userStore.me &&
      organizationStore.admins
        .map((admin) => admin.id)
        .includes(userStore.me.id)) ??
    false;
  return (
    <Page title={organizationName}>
      <Card title="Users">
        <ResourceList
          resourceName={{ singular: 'user', plural: 'users' }}
          items={organizationStore.members}
          renderItem={(item) => {
            return <UserItem user={item} isAdmin={isAdmin} />;
          }}
        />
      </Card>
    </Page>
  );
});

export default Organization;
