import ProjectStore from '@/stores/ProjectStore';
import RemoteCachePageStore from '../RemoteCachePageStore';
import { S3Bucket, Project } from '@/models';
import { S3BucketInfoFragment } from '@/graphql/types';
import { copyToClipboard } from '@/utilities/copyToClipboard';

jest.mock('@apollo/client');
jest.mock('@/stores/ProjectStore');
jest.mock('@/utilities/copyToClipboard');

describe('RemoteCachePageStore', () => {
  let projectStore: ProjectStore;
  let client: any;
  let mockProject: Project;

  beforeEach(() => {
    jest.clearAllMocks();
    client = {
      query: jest.fn(),
      mutate: jest.fn(),
    } as any;
    mockProject = {
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
    projectStore = {
      project: mockProject,
    } as ProjectStore;
  });

  it('keeps apply changes button disabled when not all fields are filled', () => {
    // Given
    const remoteCachePageStore = new RemoteCachePageStore(
      client,
      projectStore,
    );

    // When
    remoteCachePageStore.bucketName = '1';
    remoteCachePageStore.accessKeyId = '1';

    // Then
    expect(
      remoteCachePageStore.isApplyChangesButtonDisabled,
    ).toBeTruthy();
  });

  it('marks apply changes button enabled when all fields are filled', () => {
    // Given
    const remoteCachePageStore = new RemoteCachePageStore(
      client,
      projectStore,
    );

    // When
    remoteCachePageStore.bucketName = '1';
    remoteCachePageStore.accessKeyId = '1';
    remoteCachePageStore.secretAccessKey = '1';
    remoteCachePageStore.region = '1';

    // Then
    expect(
      remoteCachePageStore.isApplyChangesButtonDisabled,
    ).toBeFalsy();
  });

  it('isDefaultBucket when remoteCacheStorage is null', () => {
    // Given
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

    // When
    const remoteCachePageStore = new RemoteCachePageStore(
      client,
      projectStore,
    );

    // Then
    expect(remoteCachePageStore.isDefaultBucket).toBe(true);
    expect(remoteCachePageStore.selectedOption).toBe('default');
    expect(remoteCachePageStore.isCreatingBucket).toBe(false);
  });

  it('creates a new bucket', async () => {
    // Given
    const remoteCachePageStore = new RemoteCachePageStore(
      client,
      projectStore,
    );
    client.mutate.mockReturnValueOnce({
      data: {
        createS3Bucket: {
          accessKeyId: 'access-key-id',
          accountId: 'account-id',
          id: 'id-1',
          name: 'S3 bucket',
          secretAccessKey: 'secret',
          region: 'region',
          __typename: 'S3Bucket',
        },
      },
    });
    const expectedS3Bucket: S3Bucket = {
      accessKeyId: 'access-key-id',
      id: 'id-1',
      name: 'S3 bucket',
      secretAccessKey: 'secret',
      region: 'region',
    };

    // When
    remoteCachePageStore.projectStore.project = {
      ...mockProject,
      remoteCacheStorage: expectedS3Bucket,
    };
    remoteCachePageStore.bucketCreated(expectedS3Bucket);

    // Then
    expect(remoteCachePageStore.s3Buckets).toEqual([
      expectedS3Bucket,
    ]);
    expect(remoteCachePageStore.selectedOption).toEqual('S3 bucket');
  });

  it('returns remote cache storage name if it is set in the project', () => {
    // Given
    projectStore.project = {
      ...mockProject,
      remoteCacheStorage: {
        accessKeyId: 'accessKeyId',
        id: 'id',
        name: 'bucket',
        secretAccessKey: 'secret',
        region: 'region',
      },
    };

    // When
    const remoteCachePageStore = new RemoteCachePageStore(
      client,
      projectStore,
    );

    // Then
    expect(remoteCachePageStore.selectedOption).toEqual('bucket');
  });

  it('copy pastes project token of the remote cache', () => {
    // Given
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
      token: 'token',
      name: 'project',
      slug: 'org/project',
    };
    const remoteCachePageStore = new RemoteCachePageStore(
      client,
      projectStore,
    );

    // When
    remoteCachePageStore.copyProjectToken();

    // Then
    expect(copyToClipboard as jest.Mock).toHaveBeenCalledWith(
      'token',
    );
    expect(remoteCachePageStore.isCopyProjectButtonLoading).toBe(
      true,
    );
    jest.advanceTimersByTime(1000);
    expect(remoteCachePageStore.isCopyProjectButtonLoading).toBe(
      false,
    );
  });

  it('updates bucket after option is selected', async () => {
    // Given
    projectStore.project = {
      ...mockProject,
      remoteCacheStorage: {
        accessKeyId: 'key-id-1',
        id: 'id-1',
        name: 'S3 bucket',
        secretAccessKey: 'secret',
        region: 'region',
      },
    };
    const remoteCachePageStore = new RemoteCachePageStore(
      client,
      projectStore,
    );
    expect(remoteCachePageStore.selectedOption).toBe('S3 bucket');

    // When
    remoteCachePageStore.handleSelectOption('default');

    // Then
    expect(remoteCachePageStore.selectedOption).toBe('default');
    expect(client.mutate).toHaveBeenCalledWith({
      variables: {
        input: { projectId: 'project' },
      },
    });
  });

  it('loads remote cache page', async () => {
    // Given
    projectStore.project = {
      ...mockProject,
      remoteCacheStorage: {
        accessKeyId: 'key-id-1',
        id: 'id-1',
        name: 'S3 bucket one',
        secretAccessKey: 'secret',
        region: 'region',
      },
    };
    const remoteCachePageStore = new RemoteCachePageStore(
      client,
      projectStore,
    );
    client.query.mockResolvedValueOnce({
      data: {
        s3Buckets: [
          {
            accessKeyId: 'key-id-1',
            accountId: 'account-id-1',
            id: 'id-1',
            name: 'S3 bucket one',
            region: 'region',
            __typename: 'S3Bucket',
          },
          {
            accessKeyId: 'key-id-2',
            accountId: 'account-id-2',
            id: 'id-2',
            name: 'S3 bucket two',
            region: 'region',
            __typename: 'S3Bucket',
          },
        ] as S3BucketInfoFragment[],
      },
    });

    // When
    await remoteCachePageStore.load();

    // Then
    expect(remoteCachePageStore.bucketName).toEqual('S3 bucket one');
    expect(remoteCachePageStore.accessKeyId).toEqual('key-id-1');
    expect(remoteCachePageStore.secretAccessKey).toEqual('secret');
    expect(remoteCachePageStore.s3Buckets).toEqual([
      {
        accessKeyId: 'key-id-1',
        secretAccessKey: undefined,
        id: 'id-1',
        name: 'S3 bucket one',
        region: 'region',
      },
      {
        accessKeyId: 'key-id-2',
        secretAccessKey: undefined,
        id: 'id-2',
        name: 'S3 bucket two',
        region: 'region',
      },
    ]);
    expect(remoteCachePageStore.bucketOptions).toEqual([
      {
        label: 'Default bucket',
        value: 'default',
      },
      {
        label: 'S3 bucket one',
        value: 'S3 bucket one',
      },
      {
        label: 'S3 bucket two',
        value: 'S3 bucket two',
      },
    ]);
  });

  it('resets fields when changing reloading and project has no remote cache storage', async () => {
    // Given
    projectStore.project = {
      ...mockProject,
      remoteCacheStorage: {
        accessKeyId: 'key-id-1',
        id: 'id-1',
        name: 'S3 bucket one',
        secretAccessKey: 'secret',
        region: 'region',
      },
    };
    const remoteCachePageStore = new RemoteCachePageStore(
      client,
      projectStore,
    );
    client.query.mockResolvedValueOnce({
      data: {
        s3Buckets: [
          {
            accessKeyId: 'key-id-1',
            accountId: 'account-id-1',
            id: 'id-1',
            name: 'S3 bucket one',
            region: 'region',
            __typename: 'S3Bucket',
          },
        ] as S3BucketInfoFragment[],
      },
    });
    await remoteCachePageStore.load();
    remoteCachePageStore.projectStore.project = {
      ...mockProject,
      remoteCacheStorage: null,
    };
    client.query.mockResolvedValueOnce({
      data: {
        s3Buckets: [],
      },
    });

    // When
    await remoteCachePageStore.load();

    // Then
    expect(remoteCachePageStore.bucketName).toEqual('');
    expect(remoteCachePageStore.accessKeyId).toEqual('');
    expect(remoteCachePageStore.secretAccessKey).toEqual('');
    expect(remoteCachePageStore.s3Buckets).toEqual([]);
    expect(remoteCachePageStore.bucketOptions).toEqual([
      {
        label: 'Default bucket',
        value: 'default',
      },
    ]);
  });

  it('updates the current bucket', async () => {
    // Given
    projectStore.project = {
      ...mockProject,
      remoteCacheStorage: {
        accessKeyId: 'key-id-1',
        id: 'id-1',
        name: 'S3 bucket',
        secretAccessKey: 'secret',
        region: 'region',
      },
    };
    const remoteCachePageStore = new RemoteCachePageStore(
      client,
      projectStore,
    );
    const expectedS3Bucket: S3Bucket = {
      accessKeyId: 'changed access key id',
      id: 'id-1',
      name: 'new name',
      secretAccessKey: 'new secret',
      region: 'region',
    };
    client.mutate.mockReturnValueOnce({
      data: {
        updateS3Bucket: {
          accessKeyId: expectedS3Bucket.accessKeyId,
          accountId: 'account-id',
          id: expectedS3Bucket.id,
          name: expectedS3Bucket.name,
          secretAccessKey: expectedS3Bucket.secretAccessKey,
          region: expectedS3Bucket.region,
          __typename: 'S3Bucket',
        },
      },
    });
    client.query.mockResolvedValueOnce({
      data: {
        s3Buckets: [
          {
            accessKeyId: 'key-id-1',
            accountId: 'account-id',
            id: 'id-1',
            name: 'S3 bucket',
            secretAccessKey: 'secret',
            region: 'region',
            __typename: 'S3Bucket',
          },
        ] as S3BucketInfoFragment[],
      },
    });
    await remoteCachePageStore.load();

    // When
    await remoteCachePageStore.applyChangesButtonClicked(
      'account-id',
    );

    // Then
    expect(
      remoteCachePageStore.projectStore.project?.remoteCacheStorage,
    ).toEqual(expectedS3Bucket);
    expect(remoteCachePageStore.s3Buckets).toEqual([
      expectedS3Bucket,
    ]);
    expect(remoteCachePageStore.selectedOption).toEqual(
      expectedS3Bucket.name,
    );
  });

  it('clears remote cache', async () => {
    // Given
    projectStore.project = {
      ...mockProject,
      remoteCacheStorage: {
        accessKeyId: 'key-id-1',
        id: 'id-1',
        name: 'S3 bucket',
        secretAccessKey: 'secret',
        region: 'region',
      },
    };
    const remoteCachePageStore = new RemoteCachePageStore(
      client,
      projectStore,
    );
    client.mutate.mockReturnValueOnce({
      data: {},
    });

    // When
    await remoteCachePageStore.clearCache();

    // Then
    expect(client.mutate).toHaveBeenCalled();
  });

  it('clears remote cache with default bucket', async () => {
    // Given
    projectStore.project = {
      ...mockProject,
      remoteCacheStorage: null,
    };
    const remoteCachePageStore = new RemoteCachePageStore(
      client,
      projectStore,
    );
    client.mutate.mockReturnValueOnce({
      data: {},
    });

    // When
    await remoteCachePageStore.clearCache();

    // Then
    expect(client.mutate).toHaveBeenCalledWith({
      variables: {
        input: { projectSlug: 'org/project' },
      },
    });
  });

  it('sets a remote cache storage clear error', async () => {
    // Given
    projectStore.project = {
      ...mockProject,
      remoteCacheStorage: {
        accessKeyId: 'key-id-1',
        id: 'id-1',
        name: 'S3 bucket',
        secretAccessKey: 'secret',
        region: 'region',
      },
    };
    const remoteCachePageStore = new RemoteCachePageStore(
      client,
      projectStore,
    );
    client.mutate.mockReturnValueOnce({
      data: {
        clearRemoteCacheStorage: {
          errors: [{ message: 'Some error' }],
        },
      },
    });

    // When
    await remoteCachePageStore.clearCache();

    // Then
    expect(remoteCachePageStore.remoteCacheStorageCleanError).toBe(
      'Some error',
    );
  });
});
