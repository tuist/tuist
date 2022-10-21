import { MyAccountsQuery } from '@/graphql/types';
import { NewProjectPageStore } from '../NewProjectPageStore';

jest.mock('@apollo/client');

describe('NewProjectPageStore', () => {
  const client = {
    query: jest.fn(),
    mutate: jest.fn(),
  } as any;

  afterEach(() => {
    jest.clearAllMocks();
  });

  it('initially new project name is valid', () => {
    // Given
    const newProjectPageStore = new NewProjectPageStore(client);

    // Then
    expect(newProjectPageStore.isNewProjectNameValid).toBe(true);
  });

  it('new project name is valid when name contains only lowercase ASCII characters', () => {
    // Given
    const newProjectPageStore = new NewProjectPageStore(client);

    // When
    newProjectPageStore.projectNameChanged('projectname');

    // Then
    expect(newProjectPageStore.isNewProjectNameValid).toBe(true);
  });

  it('new project name is valid when name contains only lowercase ASCII characters and -', () => {
    // Given
    const newProjectPageStore = new NewProjectPageStore(client);

    // When
    newProjectPageStore.projectNameChanged('project-name');

    // Then
    expect(newProjectPageStore.isNewProjectNameValid).toBe(true);
  });

  it('new project name is not valid when it contains a space', () => {
    // Given
    const newProjectPageStore = new NewProjectPageStore(client);

    // When
    newProjectPageStore.projectNameChanged('project name');

    // Then
    expect(newProjectPageStore.isNewProjectNameValid).toBe(false);
  });

  it('new project name is not valid when it contains an uppercase character', () => {
    // Given
    const newProjectPageStore = new NewProjectPageStore(client);

    // When
    newProjectPageStore.projectNameChanged('ProjectName');

    // Then
    expect(newProjectPageStore.isNewProjectNameValid).toBe(false);
  });

  it('initially organization name is valid', () => {
    // Given
    const newProjectPageStore = new NewProjectPageStore(client);

    // Then
    expect(newProjectPageStore.isOrganizationNameValid).toBe(true);
  });

  it('organization name is valid when name contains only lowercase ASCII characters', () => {
    // Given
    const newProjectPageStore = new NewProjectPageStore(client);

    // When
    newProjectPageStore.organizationNameChanged('organizationname');

    // Then
    expect(newProjectPageStore.isOrganizationNameValid).toBe(true);
  });

  it('organization name is valid when name contains only lowercase ASCII characters and -', () => {
    // Given
    const newProjectPageStore = new NewProjectPageStore(client);

    // When
    newProjectPageStore.organizationNameChanged('organization-name');

    // Then
    expect(newProjectPageStore.isOrganizationNameValid).toBe(true);
  });

  it('organization name is not valid when it contains a space', () => {
    // Given
    const newProjectPageStore = new NewProjectPageStore(client);

    // When
    newProjectPageStore.organizationNameChanged('organization name');

    // Then
    expect(newProjectPageStore.isOrganizationNameValid).toBe(false);
  });

  it('organization name is not valid when it contains an uppercase character', () => {
    // Given
    const newProjectPageStore = new NewProjectPageStore(client);

    // When
    newProjectPageStore.organizationNameChanged('OrganizationName');

    // Then
    expect(newProjectPageStore.isOrganizationNameValid).toBe(false);
  });

  it('create project button is disabled when newProjectName is empty', () => {
    // Given
    const newProjectPageStore = new NewProjectPageStore(client);

    // Then
    expect(newProjectPageStore.isCreateProjectButtonDisabled).toBe(
      true,
    );
  });

  it('create project button is disabled when newProjectName is invalid', () => {
    // Given
    const newProjectPageStore = new NewProjectPageStore(client);

    // When
    newProjectPageStore.projectNameChanged('project name');

    // Then
    expect(newProjectPageStore.isCreateProjectButtonDisabled).toBe(
      true,
    );
  });

  it('create project button is enabled when project name and organization are valid', async () => {
    // Given
    const newProjectPageStore = new NewProjectPageStore(client);
    client.query.mockResolvedValueOnce({
      data: {
        accounts: [
          {
            id: 'id-my-account',
            name: 'my-account',
          },
        ],
      } as MyAccountsQuery,
    });
    await newProjectPageStore.load();

    // When
    newProjectPageStore.projectNameChanged('project-name');

    // Then
    expect(newProjectPageStore.isCreateProjectButtonDisabled).toBe(
      false,
    );
  });
});
