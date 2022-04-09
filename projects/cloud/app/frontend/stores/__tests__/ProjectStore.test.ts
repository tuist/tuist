import {
  ProjectDetailFragment,
  ProjectDocument,
  UpdateLastVisitedProjectDocument,
} from '@/graphql/types';
import { Project } from '@/models/Project';
import ProjectStore from '../ProjectStore';

jest.mock('@apollo/client');

describe('ProjectStore', () => {
  const client = {
    query: jest.fn(),
    mutate: jest.fn(),
  } as any;
  let projectStore: ProjectStore;

  beforeEach(() => {
    jest.clearAllMocks();
    projectStore = new ProjectStore(client);
  });

  it('loads a project', async () => {
    // Given
    client.query.mockResolvedValueOnce({
      data: {
        project: {
          id: 'id',
          account: {
            id: 'account-id',
            name: 'account-name',
            owner: {
              id: 'user-id',
              __typename: 'User',
            },
            __typename: 'Account',
          },
          name: 'project',
          slug: 'account-name/project',
          token: '',
          remoteCacheStorage: null,
          __typename: 'Project',
        } as ProjectDetailFragment,
      },
    });

    // When
    await projectStore.load('project', 'account-name');

    // Then
    expect(client.query).toHaveBeenCalledWith({
      query: ProjectDocument,
      variables: {
        name: 'project',
        accountName: 'account-name',
      },
    });
    expect(projectStore.project).toStrictEqual({
      account: {
        id: 'account-id',
        name: 'account-name',
        owner: { id: 'user-id', type: 'user' },
      },
      id: 'id',
      name: 'project',
      slug: 'account-name/project',
      token: '',
      remoteCacheStorage: null,
    } as Project);
    expect(client.mutate).toHaveBeenCalledWith({
      document: UpdateLastVisitedProjectDocument,
      variables: {
        input: { id: 'id' },
      },
    });
  });
});
