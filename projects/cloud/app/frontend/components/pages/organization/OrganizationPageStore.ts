import OrganizationStore from '@/stores/OrganizationStore';
import { makeAutoObservable } from 'mobx';

class OrganizationPageStore {
  inviteeEmail = '';
  isInvitePopoverActive = false;

  organizationStore: OrganizationStore;

  constructor(organizationStore: OrganizationStore) {
    this.organizationStore = organizationStore;
    makeAutoObservable(this);
  }

  get isPendingInvitationsVisible() {
    return this.organizationStore.pendingInvitations.length > 0;
  }

  invitePopoverClosed() {
    this.isInvitePopoverActive = false;
  }

  inviteMemberButtonClicked() {
    this.isInvitePopoverActive = !this.isInvitePopoverActive;
  }
}

export default OrganizationPageStore;
