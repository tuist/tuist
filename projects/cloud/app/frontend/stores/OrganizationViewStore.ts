import { makeAutoObservable } from 'mobx';

class OrganizationViewStore {
  inviteeEmail = '';
  isInvitePopoverActive = false;

  constructor() {
    makeAutoObservable(this);
  }

  invitePopoverClosed() {
    this.isInvitePopoverActive = false;
  }

  inviteMemberButtonClicked() {
    this.isInvitePopoverActive = !this.isInvitePopoverActive;
  }
}

export default OrganizationViewStore;
