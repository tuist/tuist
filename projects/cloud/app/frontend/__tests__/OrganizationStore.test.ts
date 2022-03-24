import OrganizationStore from '../stores/OrganizationStore';
import { Role } from '../graphql/types';
import { UserBasicInfo } from '@/models/UserBasicInfo';
import { OrganizationDetail } from '@/models';

jest.mock('@apollo/client');

describe('OrganizationStore', () => {
  const userOne: UserBasicInfo = {
    id: 'user-1',
    email: 'user1@email.com',
    accountName: 'user-one',
    avatarUrl: '',
  };
  const userTwo: UserBasicInfo = {
    id: 'user-2',
    email: 'user2@email.com',
    accountName: 'user-two',
    avatarUrl: '',
  };
  const admin: UserBasicInfo = {
    id: 'admin',
    email: 'admin@email.com',
    accountName: 'admin',
    avatarUrl: '',
  };

  const client = {
    query: jest.fn(),
    mutate: jest.fn(),
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('loads organization', async () => {
    // Given
    const organization = {
      id: 'organization-id',
      users: [userOne, userTwo],
      admins: [admin],
      pendingInvitations: [],
    };
    const organizationStore = new OrganizationStore(client as any);
    const expectedUserOne = {
      role: Role.User,
      id: userOne.id,
      email: userOne.email,
      name: userOne.accountName,
      avatarUrl: '',
    };
    const expectedUserTwo = {
      role: Role.User,
      id: userTwo.id,
      email: userTwo.email,
      name: userTwo.accountName,
      avatarUrl: '',
    };
    const expectedAdmin = {
      role: Role.Admin,
      id: admin.id,
      email: admin.email,
      name: admin.accountName,
      avatarUrl: '',
    };

    // When
    organizationStore.organization = organization;

    // Then
    expect(organizationStore.users).toEqual([
      expectedUserOne,
      expectedUserTwo,
    ]);
    expect(organizationStore.admins).toEqual([expectedAdmin]);
    expect(organizationStore.members).toEqual([
      expectedAdmin,
      expectedUserOne,
      expectedUserTwo,
    ]);
  });

  it('changes role of a member from admin to user', async () => {
    // Given
    const organization = {
      __typename: 'Organization' as 'Organization' | undefined,
      id: 'organization-id',
      users: [userOne, userTwo],
      admins: [admin],
      pendingInvitations: [],
    };
    const organizationStore = new OrganizationStore(client as any);
    organizationStore.organization = organization;
    const expectedUserOne = {
      role: Role.User,
      id: userOne.id,
      email: userOne.email,
      name: userOne.accountName,
      avatarUrl: '',
    };
    const expectedUserTwo = {
      role: Role.User,
      id: userTwo.id,
      email: userTwo.email,
      name: userTwo.accountName,
      avatarUrl: '',
    };
    const expectedUserThree = {
      role: Role.User,
      id: admin.id,
      email: admin.email,
      name: admin.accountName,
      avatarUrl: '',
    };

    // When
    await organizationStore.changeUserRole(admin.id, Role.User);

    // Then
    expect(organizationStore.admins).toEqual([]);
    expect(organizationStore.users).toEqual([
      expectedUserOne,
      expectedUserTwo,
      expectedUserThree,
    ]);
  });

  it('removes a user from the organization', async () => {
    // Given
    const organization = {
      id: 'organization-id',
      users: [userOne, userTwo],
      admins: [admin],
      pendingInvitations: [],
    } as OrganizationDetail;
    const organizationStore = new OrganizationStore(client as any);
    organizationStore.organization = organization;
    const expectedUserOne = {
      role: Role.User,
      id: userOne.id,
      email: userOne.email,
      name: userOne.accountName,
      avatarUrl: '',
    };
    const expectedAdmin = {
      role: Role.Admin,
      id: admin.id,
      email: admin.email,
      name: admin.accountName,
      avatarUrl: '',
    };

    // When
    await organizationStore.removeMember(userTwo.id);

    // Then
    expect(organizationStore.admins).toEqual([expectedAdmin]);
    expect(organizationStore.users).toEqual([expectedUserOne]);
  });
});
