// WebAuthn ceremonies for passkeys. The server answers options as JSON with
// base64url-encoded binary fields and an encrypted ceremony token; results
// are posted back with that token as ordinary forms, so sign-in keeps the
// server's redirects and session handling.

const toBytes = (value) => Uint8Array.from(atob(value.replace(/-/g, "+").replace(/_/g, "/")), (c) => c.charCodeAt(0));

const toBase64url = (buffer) =>
  btoa(String.fromCharCode(...new Uint8Array(buffer)))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");

const descriptors = (credentials) => credentials.map((credential) => ({ ...credential, id: toBytes(credential.id) }));

export const passkeysSupported = () => typeof window.PublicKeyCredential === "function";

async function fetchOptions(url) {
  const response = await fetch(url, {
    method: "POST",
    headers: { "x-csrf-token": document.querySelector("meta[name='csrf-token']").content },
    credentials: "same-origin",
  });
  if (!response.ok) {
    const error = new Error(`Passkey options request failed with ${response.status}`);
    error.name = "PasskeyOptionsError";
    error.status = response.status;
    // The server explains refusals it can predict, such as a stale session,
    // before the browser saves a credential that could never be used.
    const body = await response.json().catch(() => ({}));
    error.serverMessage = body.error;
    if (body.reauthenticate) window.location.reload();
    throw error;
  }
  return response.json();
}

function submit(action, fields) {
  const form = document.createElement("form");
  form.method = "post";
  form.action = action;
  form.hidden = true;
  const values = { _csrf_token: document.querySelector("meta[name='csrf-token']").content, ...fields };
  for (const [name, value] of Object.entries(values)) {
    const input = document.createElement("input");
    input.type = "hidden";
    input.name = name;
    input.value = value ?? "";
    form.append(input);
  }
  document.body.append(form);
  form.submit();
}

async function authenticate({ optionsURL, actionURL, mediation, signal }) {
  const { publicKey: options, token } = await fetchOptions(optionsURL);
  const credential = await navigator.credentials.get({
    mediation,
    signal,
    publicKey: {
      ...options,
      challenge: toBytes(options.challenge),
      allowCredentials: descriptors(options.allowCredentials),
    },
  });
  submit(actionURL, {
    challenge_token: token,
    credential_id: toBase64url(credential.rawId),
    client_data_json: toBase64url(credential.response.clientDataJSON),
    authenticator_data: toBase64url(credential.response.authenticatorData),
    signature: toBase64url(credential.response.signature),
    user_handle: credential.response.userHandle ? toBase64url(credential.response.userHandle) : "",
  });
}

async function register({ optionsURL, actionURL, name }) {
  const { publicKey: options, token } = await fetchOptions(optionsURL);
  const credential = await navigator.credentials.create({
    publicKey: {
      ...options,
      challenge: toBytes(options.challenge),
      user: { ...options.user, id: toBytes(options.user.id) },
      excludeCredentials: descriptors(options.excludeCredentials),
    },
  });
  submit(actionURL, {
    challenge_token: token,
    name,
    attestation_object: toBase64url(credential.response.attestationObject),
    client_data_json: toBase64url(credential.response.clientDataJSON),
    transports: credential.response.getTransports?.().join(",") ?? "",
  });
}

function reportFailure(status, error) {
  // Cancelling the browser prompt is not an error worth showing.
  if (error?.name === "AbortError" || !status) return;
  const messages = {
    NotAllowedError: status.dataset.cancelled,
    InvalidStateError: status.dataset.alreadyRegistered,
  };
  status.textContent = error?.serverMessage || messages[error?.name] || status.dataset.failed;
}

// Settings and the MFA challenge are controller-rendered pages without a
// LiveView socket, so their buttons are wired directly on load.
export function initPasskeys() {
  const button = document.querySelector("[data-passkey-ceremony]");
  if (!button) return;
  const status = document.getElementById(button.dataset.status);
  if (!passkeysSupported()) {
    button.disabled = true;
    if (status) status.textContent = status.dataset.unsupported ?? "";
    return;
  }
  button.addEventListener("click", async () => {
    const { optionsUrl: optionsURL, actionUrl: actionURL, passkeyCeremony } = button.dataset;
    if (status) status.textContent = "";
    // The button stays disabled once a ceremony succeeds, while the form posts.
    button.disabled = true;
    try {
      if (passkeyCeremony === "register") {
        const name = document.getElementById(button.dataset.nameInput)?.value ?? "";
        await register({ optionsURL, actionURL, name });
      } else {
        await authenticate({ optionsURL, actionURL });
      }
    } catch (error) {
      button.disabled = false;
      // The pending MFA challenge expired; the server restarts sign-in.
      if (passkeyCeremony !== "register" && error?.status === 404) {
        window.location.assign("/users/log_in");
        return;
      }
      reportFailure(status, error);
    }
  });
}

// The sign-in page offers passkeys both as a button and in the email field's
// autofill (conditional mediation). Starting the button's request aborts the
// pending autofill request, since a page can only run one at a time.
export const PasskeyLogin = {
  mounted() {
    if (!passkeysSupported()) return;
    this.el.hidden = false;
    const { optionsUrl: optionsURL, actionUrl: actionURL } = this.el.dataset;
    const status = this.el.querySelector("[role='status']");

    const button = this.el.querySelector("button");

    this.startAutofill = async () => {
      // Create the controller first so a click during the availability check
      // still aborts this request.
      const autofill = new AbortController();
      this.autofill = autofill;
      if (!(await PublicKeyCredential.isConditionalMediationAvailable?.()) || autofill.signal.aborted) return;
      authenticate({ optionsURL, actionURL, mediation: "conditional", signal: autofill.signal }).catch(() => {});
    };

    button.addEventListener("click", async () => {
      if (button.disabled) return;
      button.disabled = true;
      this.autofill?.abort();
      status.textContent = "";
      try {
        await authenticate({ optionsURL, actionURL });
      } catch (error) {
        button.disabled = false;
        reportFailure(status, error);
        this.startAutofill();
      }
    });

    this.startAutofill();
  },
  destroyed() {
    this.autofill?.abort();
  },
};
