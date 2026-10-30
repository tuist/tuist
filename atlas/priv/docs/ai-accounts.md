Connect your [Claude](https://claude.ai/) or [ChatGPT](https://chatgpt.com/) account so sessions you start will use your connected account for inference: running the AI model and generating its responses. The connection belongs to you, not the workspace.

Conversations with Pip in Orbit use your connected ChatGPT account first, then Claude. If neither is connected or a provider is unavailable, Atlas can use the workspace's configured Orbit inference profile. Other people's credentials are never used for your messages. Conversation context and authorized tool results are shared with whichever provider handles the turn, including a fallback after an unsuccessful attempt. Credentials remain encrypted and are never displayed again.

On the web, open your avatar menu, choose **Account settings**, then **AI accounts**. Select **Connect account** to get started.

On iOS or Android, open **Settings** and choose **Claude** or **ChatGPT** in the **AI accounts** section. The apps manage connections directly on your selected Atlas server; you do not need to sign in to the web dashboard. ChatGPT authorization still opens OpenAI's website.

## Connect Claude

1. Install [Claude Code](https://code.claude.com/docs/en/setup) on your computer.
2. Run `claude setup-token` and follow the sign-in instructions.
3. Choose **Claude** in mobile **Settings**, or in the web's **Connect account** dialog.
4. Paste the generated token and select **Save connection**.

Use a Claude Code subscription token, not an Anthropic API key. **Credentials saved** means Atlas stored the token, not that Claude has verified access. Your subscription's terms and eligibility still apply.

## Connect ChatGPT

1. Choose **ChatGPT** and select **Sign in with ChatGPT**.
2. Open the displayed OpenAI link and enter the one-time code. Only authorize a sign-in you started yourself. Atlas never asks for your OpenAI password.
3. Return to Atlas. Once authorization succeeds, the account's status changes to **Credentials saved**.

The code expires after 15 minutes. Closing setup or leaving the mobile ChatGPT settings page cancels the pending sign-in without replacing an existing connection.

If sign-in is disabled, ask your Atlas administrator to [enable ChatGPT sign-in](/docs/self-hosting#enable-chatgpt-sign-in).

## Manage connected accounts

On the web, use the menu next to a connected account. On mobile, open the account's settings.

- To replace credentials, choose **Update credentials** on the web, or save a new Claude token or repeat ChatGPT sign-in on mobile. For ChatGPT, the previous connection stays in place until you finish signing in again.
- **Disconnect** deletes Atlas's saved credentials. It does not revoke access at Claude or OpenAI; do that separately in your account settings with the service.

To manage connections from a tool client instead of the dashboard, see the [MCP reference for AI accounts](/docs/ai-account-tools).
