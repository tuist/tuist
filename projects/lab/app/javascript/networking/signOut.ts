import { signOutPath } from '../utilities/routes';
import restClient from './restClient';

export const redirectToSignIn = () => {
  window.location.pathname = '/';
};

const signOut = async () => {
  try {
    await restClient.delete(signOutPath);
  } catch {
    console.log('Logged out');
  }
  redirectToSignIn();
};

export default signOut;
