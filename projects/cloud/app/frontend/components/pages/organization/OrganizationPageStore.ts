import { makeAutoObservable } from 'mobx';

class OrganizationPageStore {
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

export default OrganizationPageStore;
