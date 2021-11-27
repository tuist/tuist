import { onError } from '@apollo/client/link/error';
import { redirectToSignIn } from '../utilities/signOut';
import type { ServerError, ServerParseError } from '@apollo/client';

export const logoutIfError = (
  networkError: Error | ServerError | ServerParseError | undefined,
): void => {
  if (
    // @ts-ignore
    (networkError && networkError.statusCode === 401) ||
    // @ts-ignore
    (networkError && networkError.statusCode === 422)
  ) {
    redirectToSignIn();
  }
};

const logoutLink = onError(({ networkError }) =>
  // @ts-ignore
  logoutIfError(networkError),
);

export default logoutLink;
