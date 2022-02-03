import RemoteCachePageStore from '../RemoteCachePageStore';

jest.mock('@apollo/client');

describe('RemoteCachePageStore', () => {
  const client = {
    query: jest.fn(),
    mutate: jest.fn(),
  } as any;

  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('keeps apply changes button disabled when not all fields are filled', async () => {
    // Given
    const remoteCachePageStore = new RemoteCachePageStore(client);

    // When
    remoteCachePageStore.bucketName = '1';
    remoteCachePageStore.accessKeyId = '1';

    // Then
    expect(
      remoteCachePageStore.isApplyChangesButtonDisabled,
    ).toBeTruthy();
  });

  it('marks apply changes button enabled when all fields are filled', async () => {
    // Given
    const remoteCachePageStore = new RemoteCachePageStore(client);

    // When
    remoteCachePageStore.bucketName = '1';
    remoteCachePageStore.accessKeyId = '1';
    remoteCachePageStore.secretAccessKey = '1';

    // Then
    expect(
      remoteCachePageStore.isApplyChangesButtonDisabled,
    ).toBeFalsy();
  });
});
