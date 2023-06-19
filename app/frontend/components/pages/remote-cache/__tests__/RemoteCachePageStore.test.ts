import ProjectStore from '@/stores/ProjectStore';
import RemoteCachePageStore from '../RemoteCachePageStore';
import { S3Bucket } from '@/models';
import { S3BucketInfoFragment } from '@/graphql/types';
import { copyToClipboard } from '@/utilities/copyToClipboard';

jest.mock('@apollo/client');
jest.mock('@/stores/ProjectStore');
jest.mock('@/utilities/copyToClipboard');

describe('RemoteCachePageStore', () => {
  const client = {
    query: jest.fn(),
    mutate: jest.fn(),
  } as any;
  const projectStore = {} as ProjectStore;

  beforeEach(() => {
    jest.clearAllMocks();
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

  it('returns new as selected option when remoteCacheStorage is null', () => {
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
    expect(remoteCachePageStore.selectedOption).toEqual('new');
    expect(remoteCachePageStore.isCreatingBucket).toBeTruthy();
  });

  it('returns remote cache storage name if it is set in the project', () => {
    // Given
    projectStore.project!.remoteCacheStorage = {
      accessKeyId: 'accessKeyId',
      id: 'id',
      name: 'bucket',
      secretAccessKey: 'secret',
      region: 'region',
      isDefault: false,
    };

    // When
    const remoteCachePageStore = new RemoteCachePageStore(
      client,
      projectStore,
    );

    // Then
    expect(remoteCachePageStore.selectedOption).toEqual('bucket');
  });

  it('changes isDefaultBucket to false when going from a default bucket to creating a new one', async () => {
    // Given
    projectStore.project!.remoteCacheStorage = {
      accessKeyId: 'accessKeyId',
      id: 'id',
      name: 'bucket',
      secretAccessKey: 'secret',
      region: 'region',
      isDefault: true,
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
            id: 'id',
            name: 'S3 bucket one',
            region: 'region',
            isDefault: true,
            __typename: 'S3Bucket',
          },
        ] as S3BucketInfoFragment[],
      },
    });
    await remoteCachePageStore.load();

    // When
    remoteCachePageStore.handleSelectOption('new');

    // Then
    expect(remoteCachePageStore.isDefaultBucket).toEqual(false);
  });

  it('sets isDefaultBucket to true', async () => {
    // Given
    projectStore.project!.remoteCacheStorage = {
      accessKeyId: 'accessKeyId',
      id: 'id',
      name: 'bucket',
      secretAccessKey: 'secret',
      region: 'region',
      isDefault: true,
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
            id: 'id',
            name: 'S3 bucket one',
            region: 'region',
            isDefault: true,
            __typename: 'S3Bucket',
          },
        ] as S3BucketInfoFragment[],
      },
    });

    // When
    await remoteCachePageStore.load();

    // Then
    expect(remoteCachePageStore.isDefaultBucket).toEqual(true);
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

  it('loads remote cache page', async () => {
    // Given
    projectStore.project!.remoteCacheStorage = {
      accessKeyId: 'key-id-1',
      id: 'id-1',
      name: 'S3 bucket one',
      secretAccessKey: 'secret',
      region: 'region',
      isDefault: false,
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
        label: 'Create new bucket',
        value: 'new',
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
    projectStore.project!.remoteCacheStorage = {
      accessKeyId: 'key-id-1',
      id: 'id-1',
      name: 'S3 bucket one',
      secretAccessKey: 'secret',
      region: 'region',
      isDefault: false,
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
    remoteCachePageStore.projectStore.project!.remoteCacheStorage =
      null;
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
        label: 'Create new bucket',
        value: 'new',
      },
    ]);
  });

  it('creates a new bucket', async () => {
    // Given
    const remoteCachePageStore = new RemoteCachePageStore(
      client,
      projectStore,
    );
    remoteCachePageStore.bucketName = 'S3 bucket';
    remoteCachePageStore.secretAccessKey = 'secret';
    remoteCachePageStore.accessKeyId = 'access-key-id';
    remoteCachePageStore.region = 'region';
    client.mutate.mockReturnValueOnce({
      data: {
        createS3Bucket: {
          accessKeyId: 'access-key-id',
          accountId: 'account-id',
          id: 'id-1',
          name: 'S3 bucket',
          secretAccessKey: 'secret',
          region: 'region',
          isDefault: false,
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
      isDefault: false,
    };

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
  });

  it('updates the current bucket', async () => {
    // Given
    projectStore.project!.remoteCacheStorage = {
      accessKeyId: 'key-id-1',
      id: 'id-1',
      name: 'S3 bucket',
      secretAccessKey: 'secret',
      region: 'region',
      isDefault: false,
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
      isDefault: false,
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
          isDefault: expectedS3Bucket.isDefault,
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
    projectStore.project!.remoteCacheStorage = {
      accessKeyId: 'key-id-1',
      id: 'id-1',
      name: 'S3 bucket',
      secretAccessKey: 'secret',
      region: 'region',
      isDefault: false,
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

  it('sets a remote cache storage clear error', async () => {
    // Given
    projectStore.project!.remoteCacheStorage = {
      accessKeyId: 'key-id-1',
      id: 'id-1',
      name: 'S3 bucket',
      secretAccessKey: 'secret',
      region: 'region',
      isDefault: false,
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
