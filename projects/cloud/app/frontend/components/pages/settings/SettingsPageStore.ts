import ProjectStore from '@/stores/ProjectStore';
import { makeAutoObservable } from 'mobx';

class SettingsPageStore {
  isDeleteProjectConfirmModalActive = false;
  currentProjectSlugToDelete = '';

  private projectStore: ProjectStore;

  constructor(projectStore: ProjectStore) {
    this.projectStore = projectStore;
    makeAutoObservable(this);
  }

  deleteProjectConfirmModalDismissed() {
    this.isDeleteProjectConfirmModalActive = false;
    this.currentProjectSlugToDelete = '';
  }
}

export default SettingsPageStore;
