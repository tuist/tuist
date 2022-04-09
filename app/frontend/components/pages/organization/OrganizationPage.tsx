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
  FormLayout,
  TextField,
} from '@shopify/polaris';
import { useParams } from 'react-router';
import { Role, Organization as _ } from '@/graphql/types';
import { observer } from 'mobx-react-lite';
import { HomeStoreContext } from '@/stores/HomeStore';
import OrganizationPageStore from './OrganizationPageStore';

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
  const { organizationStore, userStore } =
    useContext(HomeStoreContext);
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
        {isAdmin && user.id !== userStore.me?.id ? (
          <UserRolePopover user={user} />
        ) : (
          <TextStyle>
            {user.role.charAt(0).toUpperCase() + user.role.slice(1)}
          </TextStyle>
        )}
        {isAdmin && (
          <Button
            destructive={true}
            onClick={() => {
              organizationStore.removeMember(user.id);
            }}
          >
            Remove member
          </Button>
        )}
      </Stack>
    </div>
  );
};

const OrganizationPage = observer(() => {
  const { accountName: organizationName } = useParams();
  const homeStore = useContext(HomeStoreContext);
  const { organizationStore, userStore } = homeStore;
  const [organizationPageStore] = useState(
    () => new OrganizationPageStore(organizationStore),
  );
  return (
    <Page
      primaryAction={
        <Popover
          active={organizationPageStore.isInvitePopoverActive}
          activator={
            <Button
              primary
              onClick={() => {
                organizationPageStore.inviteMemberButtonClicked();
              }}
            >
              Invite member
            </Button>
          }
          onClose={() => {
            organizationPageStore.invitePopoverClosed();
          }}
          sectioned
        >
          <FormLayout>
            <TextField
              label="Invitee email"
              value={organizationPageStore.inviteeEmail}
              onChange={(newValue) => {
                organizationPageStore.inviteeEmail = newValue;
              }}
            />
            <Button
              primary
              onClick={() => {
                organizationStore.inviteMember(
                  organizationPageStore.inviteeEmail,
                );
                organizationPageStore.invitePopoverClosed();
              }}
            >
              Invite member
            </Button>
          </FormLayout>
        </Popover>
      }
      title={organizationName}
    >
      <Card title="Members">
        <ResourceList
          resourceName={{ singular: 'member', plural: 'members' }}
          items={organizationStore.members}
          renderItem={(item) => {
            return (
              <UserItem user={item} isAdmin={homeStore.isAdmin} />
            );
          }}
        />
      </Card>
      {organizationPageStore.isPendingInvitationsVisible && (
        <Card title="Pending invitations">
          <ResourceList
            resourceName={{
              singular: 'pending invitation',
              plural: 'pending invitations',
            }}
            items={
              organizationStore.organization?.pendingInvitations ?? []
            }
            renderItem={({ inviteeEmail, id }) => {
              return (
                <div style={{ padding: '10px 100px 10px 20px' }}>
                  <Stack alignment={'center'}>
                    <Avatar customer size="medium" />
                    <Stack.Item fill={true}>
                      <TextStyle variation="strong">
                        {inviteeEmail}
                      </TextStyle>
                    </Stack.Item>

                    {homeStore.isAdmin && (
                      <Stack>
                        <Button
                          onClick={() => {
                            organizationStore.resendInvite(id);
                          }}
                        >
                          Resend invite
                        </Button>
                        <Button
                          destructive
                          onClick={() => {
                            organizationStore.cancelInvite(id);
                          }}
                        >
                          Cancel invite
                        </Button>
                      </Stack>
                    )}
                  </Stack>
                </div>
              );
            }}
          />
        </Card>
      )}
    </Page>
  );
});

export default OrganizationPage;
