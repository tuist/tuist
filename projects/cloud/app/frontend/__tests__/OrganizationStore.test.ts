import OrganizationStore from '../stores/OrganizationStore';
import { Role } from '../graphql/types';

jest.mock('@apollo/client');

describe('OrganizationStore', () => {
  const userOne = {
    id: 'user-1',
    email: 'user1@email.com',
    name: 'User One',
    account: { name: 'user-one' },
  };
  const userTwo = {
    id: 'user-2',
    email: 'user2@email.com',
    name: 'User Two',
    account: { name: 'user-two' },
  };
  const admin = {
    id: 'admin',
    email: 'admin@email.com',
    name: 'Admin',
    account: { name: 'admin' },
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
      __typename: 'Organization' as 'Organization' | undefined,
      id: 'organization-id',
      users: [userOne, userTwo],
      admins: [admin],
    };
    const organizationStore = new OrganizationStore(client as any);
    const expectedUserOne = {
      role: Role.User,
      id: userOne.id,
      email: userOne.email,
      name: userOne.account.name,
      avatarUrl: undefined,
    };
    const expectedUserTwo = {
      role: Role.User,
      id: userTwo.id,
      email: userTwo.email,
      name: userTwo.account.name,
      avatarUrl: undefined,
    };
    const expectedAdmin = {
      role: Role.Admin,
      id: admin.id,
      email: admin.email,
      name: admin.account.name,
      avatarUrl: undefined,
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
    };
    const organizationStore = new OrganizationStore(client as any);
    organizationStore.organization = organization;
    const expectedUserOne = {
      role: Role.User,
      id: userOne.id,
      email: userOne.email,
      name: userOne.account.name,
      avatarUrl: undefined,
    };
    const expectedUserTwo = {
      role: Role.User,
      id: userTwo.id,
      email: userTwo.email,
      name: userTwo.account.name,
      avatarUrl: undefined,
    };
    const expectedUserThree = {
      role: Role.User,
      id: admin.id,
      email: admin.email,
      name: admin.account.name,
      avatarUrl: undefined,
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
      __typename: 'Organization' as 'Organization' | undefined,
      id: 'organization-id',
      users: [userOne, userTwo],
      admins: [admin],
    };
    const organizationStore = new OrganizationStore(client as any);
    organizationStore.organization = organization;
    const expectedUserOne = {
      role: Role.User,
      id: userOne.id,
      email: userOne.email,
      name: userOne.account.name,
      avatarUrl: undefined,
    };
    const expectedAdmin = {
      role: Role.Admin,
      id: admin.id,
      email: admin.email,
      name: admin.account.name,
      avatarUrl: undefined,
    };

    // When
    await organizationStore.removeMember(userTwo.id);

    // Then
    expect(organizationStore.admins).toEqual([expectedAdmin]);
    expect(organizationStore.users).toEqual([expectedUserOne]);
  });
});
