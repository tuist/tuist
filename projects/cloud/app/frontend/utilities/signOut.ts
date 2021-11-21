export const redirectToSignIn = () => {
  window.location.pathname = '/users/sign_in';
};

const signOut = async () => {
  redirectToSignIn();
};

export default signOut;
