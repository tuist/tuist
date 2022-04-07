import ProjectStore from '@/stores/ProjectStore';
import UserStore from '@/stores/UserStore';
import { makeAutoObservable } from 'mobx';

class SettingsPageStore {
  isDeleteProjectConfirmModalActive = false;
  currentProjectSlugToDelete = '';

  private projectStore: ProjectStore;
  private userStore: UserStore;

  constructor(projectStore: ProjectStore, userStore: UserStore) {
    this.projectStore = projectStore;
    this.userStore = userStore;
    makeAutoObservable(this);
  }

  deleteProjectConfirmModalDismissed() {
    this.isDeleteProjectConfirmModalActive = false;
    this.currentProjectSlugToDelete = '';
  }

  async deleteProjectConfirmed() {
    await this.projectStore.deleteProject();
    await this.userStore.load();
    const slug =
      this.userStore.me?.lastVisitedProject?.slug ??
      this.userStore.me?.projects[0].slug;
    return slug;
  }

  get isDeleteProjectButtonDisabled() {
    return (
      this.currentProjectSlugToDelete !==
      this.projectStore.project?.slug
    );
  }
}

export default SettingsPageStore;
