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
import {
  Role,
  Organization as _,
  useChangeUserRoleMutation,
  useOrganizationQuery,
  useMeQuery,
} from '@/graphql/types';

interface User {
  id: string;
  email: string;
  name: string;
  avatarUrl: string | undefined;
  role: Role;
}

const UserRolePopover = ({
  user,
  organizationId,
}: {
  user: User;
  organizationId: string;
}) => {
  // TODO: Enable actually changing the role
  const [isRolePopoverActive, setRolePopoverActive] = useState(false);
  const toggleRolePopoverActive = useCallback(
    () => setRolePopoverActive((active) => !active),
    [],
  );

  const [newRole, setNewRole] = useState(user.role);
  const [currentRole, setCurrentRole] = useState(user.role);
  const [changeUserRoleMutation] = useChangeUserRoleMutation({
    onCompleted: () => {
      setCurrentRole(newRole);
    },
  });
  const changeRole = useCallback(({ newRole }: { newRole: Role }) => {
    changeUserRoleMutation({
      variables: {
        input: {
          userId: user.id,
          organizationId: organizationId,
          role: newRole,
        },
      },
    });
    toggleRolePopoverActive();
    setNewRole(newRole);
  }, []);

  return (
    <div style={{ width: 100 }}>
      <Popover
        active={isRolePopoverActive}
        activator={
          <Button disclosure onClick={toggleRolePopoverActive}>
            {currentRole.charAt(0).toUpperCase() +
              currentRole.slice(1)}
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
};

const UserItem = ({
  user,
  organizationId,
  isAdmin,
}: {
  user: User;
  organizationId: string;
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
          <UserRolePopover
            user={user}
            organizationId={organizationId}
          />
        ) : (
          <TextStyle>
            {user.role.charAt(0).toUpperCase() + user.role.slice(1)}
          </TextStyle>
        )}
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
        id: user.id,
        email: user.email,
        name: user.account.name,
        avatarUrl: user.avatarUrl ?? undefined,
        role: Role.User,
      };
    }) ?? [];

  const admins =
    organization?.admins.map((user) => {
      return {
        id: user.id,
        email: user.email,
        name: user.account.name,
        avatarUrl: user.avatarUrl ?? undefined,
        role: Role.Admin,
      };
    }) ?? [];
  const user = useMeQuery().data?.me;
  const isAdmin =
    (user && admins.map((admin) => admin.id).includes(user.id)) ??
    false;
  return (
    <Page title={organizationName}>
      <Card title="Users">
        <ResourceList
          resourceName={{ singular: 'user', plural: 'users' }}
          items={users
            .concat(admins)
            .sort(
              (first, second) =>
                0 - (first.name > second.name ? -1 : 1),
            )}
          renderItem={(item) => {
            return (
              <UserItem
                user={item}
                isAdmin={isAdmin}
                organizationId={organization?.id ?? ''}
              />
            );
          }}
        />
      </Card>
    </Page>
  );
};

export default Organization;
