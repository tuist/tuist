import ProjectStore from '@/stores/ProjectStore';
import UserStore from '@/stores/UserStore';
import { ApolloClient } from '@apollo/client';
import SettingsPageStore from '../SettingsPageStore';

jest.mock('@/stores/UserStore');
jest.mock('@/stores/ProjectStore');

describe('SettingsPageStore', () => {
  let projectStore: ProjectStore;
  let userStore: UserStore;
  let settingsPageStore: SettingsPageStore;

  beforeEach(() => {
    jest.clearAllMocks();
    projectStore = new ProjectStore({} as ApolloClient<object>);
    projectStore.project = {
      id: 'project',
      account: {
        id: 'account-id',
        name: 'acount-name',
        owner: {
          id: 'owner',
          type: 'organization',
        },
      },
      remoteCacheStorage: null,
      token: '',
      name: 'project',
      slug: 'org/project',
    };
    userStore = new UserStore({} as ApolloClient<object>);
    settingsPageStore = new SettingsPageStore(
      projectStore,
      userStore,
    );
  });

  it('keeps delete project button disabled until slug and text match', () => {
    expect(settingsPageStore.isDeleteProjectButtonDisabled).toBe(
      true,
    );
    settingsPageStore.currentProjectSlugToDelete = 'org/projec';
    expect(settingsPageStore.isDeleteProjectButtonDisabled).toBe(
      true,
    );
    settingsPageStore.currentProjectSlugToDelete = 'org/project';
    expect(settingsPageStore.isDeleteProjectButtonDisabled).toBe(
      false,
    );
    settingsPageStore.currentProjectSlugToDelete = 'org/proje';
    expect(settingsPageStore.isDeleteProjectButtonDisabled).toBe(
      true,
    );
  });

  it('confirms to delete a project', async () => {
    // Given
    // @ts-ignore
    userStore.me = {
      lastVisitedProject: {
        slug: 'user/my-project',
      },
    };

    // When
    const got = await settingsPageStore.deleteProjectConfirmed();

    // Then
    expect(projectStore.deleteProject).toHaveBeenCalledTimes(1);
    expect(userStore.load).toHaveBeenCalledTimes(1);
    expect(got).toBe('user/my-project');
  });

  it('resets values when delete project confirm modal is dismissed', () => {
    // Given
    settingsPageStore.isDeleteProjectConfirmModalActive = true;
    settingsPageStore.currentProjectSlugToDelete = 'some-slug';

    // When
    settingsPageStore.deleteProjectConfirmModalDismissed();

    // Then
    expect(settingsPageStore.isDeleteProjectConfirmModalActive).toBe(
      false,
    );
    expect(settingsPageStore.currentProjectSlugToDelete).toBe('');
  });
});
