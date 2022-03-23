import { OrganizationDetail } from '@/models';
import OrganizationStore from '@/stores/OrganizationStore';
import OrganizationPageStore from '../OrganizationPageStore';

jest.mock('@/stores/OrganizationStore');

describe('OrganizationPageStore', () => {
  const organizationStore = {} as OrganizationStore;

  beforeEach(() => {
    organizationStore.organization = {
      id: 'organization',
      pendingInvitations: [],
      users: [],
      admins: [],
    } as OrganizationDetail;
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  it('sets isPendingInvitationsVisible to false when there are pending invitations', () => {
    // Given
    organizationStore.organization!.pendingInvitations = [
      { id: 'one', inviteeEmail: 'test@mail.com' },
    ];

    // When
    const organizationPageStore = new OrganizationPageStore(
      organizationStore,
    );

    // Then
    expect(organizationPageStore.isPendingInvitationsVisible).toBe(
      true,
    );
  });

  it('sets isPendingInvitationsVisible to true when there are not pending invitations', () => {
    // Given
    organizationStore.organization!.pendingInvitations = [];

    // When
    const organizationPageStore = new OrganizationPageStore(
      organizationStore,
    );

    // Then
    expect(organizationPageStore.isPendingInvitationsVisible).toBe(
      false,
    );
  });
});
