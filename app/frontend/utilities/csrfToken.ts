const csrfToken = document
  ?.querySelector('meta[name=csrf-token]')
  ?.getAttribute('content');

export default csrfToken;
