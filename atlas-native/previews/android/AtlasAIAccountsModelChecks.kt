package dev.tuist.atlas.preview

import android.content.Context
import android.os.Handler
import android.os.Looper
import dev.tuist.atlas.AtlasAIAccountsModel
import dev.tuist.atlas.AtlasAuthentication
import dev.tuist.atlas.AtlasSecureStorage
import dev.tuist.atlas.AuthFailure
import org.json.JSONObject

// Runs only inside the isolated preview app on the real Android main looper.
internal fun checkAccountModel(context: Context) {
    cancellationRefreshesAConnectionThatWonTheRace()
    lateSaveDoesNotNavigateANewerForm()
    lateCredentialErrorDoesNotLeakIntoAnotherPage()
    lateStartIsCancelled()
    recoveredCancellationCanBeRetried()
    terminalFailureStopsPolling("login_failed")
    terminalFailureStopsPolling("rejected")
    signOutQueuesBehindAccountWork(context)
}

private fun metadata(configured: Boolean = false) =
    JSONObject(
        """{"providers":[{"provider":"chatgpt","credential_configured":$configured,"login_available":true}]}""",
    )

private fun login() = JSONObject("""{"login_id":"test-only","user_code":"DEMO","interval":0}""")

private fun cancellationRefreshesAConnectionThatWonTheRace() {
    val actions = mutableListOf<String>()
    var configured = false
    val model =
        AtlasAIAccountsModel { request, complete ->
            val action = request.getString("action")
            actions.add(action)
            when (action) {
                "start_chatgpt" -> complete(Result.success(login()))
                "cancel_chatgpt" -> {
                    configured = true
                    complete(Result.failure(AuthFailure("login_expired", "Expired")))
                }
                else -> complete(Result.success(metadata(configured)))
            }
        }
    model.startSignIn()
    model.cancelLogin()
    check(actions == listOf("start_chatgpt", "cancel_chatgpt", "list"))
    check(model.metadata("chatgpt")?.getBoolean("credential_configured") == true)
    check(model.message == null && !model.busy)
}

private fun lateSaveDoesNotNavigateANewerForm() {
    lateinit var finish: (Result<JSONObject>) -> Unit
    val model =
        AtlasAIAccountsModel { request, complete ->
            if (request.getString("action") == "connect_claude") finish = complete else complete(Result.success(metadata()))
        }
    model.open("claude")
    model.saveClaude("preview-only")
    model.open("settings")
    model.open("claude")
    finish(Result.success(JSONObject()))
    check(model.page == "claude" && !model.busy)
}

private fun lateCredentialErrorDoesNotLeakIntoAnotherPage() {
    lateinit var finish: (Result<JSONObject>) -> Unit
    val model = AtlasAIAccountsModel { _, complete -> finish = complete }
    model.open("claude")
    model.saveClaude("preview-only")
    model.open("chatgpt")
    finish(Result.failure(AuthFailure("invalid_token", "Paste a Claude token")))
    check(model.message == null && !model.busy)
}

private fun lateStartIsCancelled() {
    lateinit var finish: (Result<JSONObject>) -> Unit
    var cancelled: String? = null
    val model =
        AtlasAIAccountsModel { request, complete ->
            when (request.getString("action")) {
                "start_chatgpt" -> finish = complete
                "cancel_chatgpt" -> {
                    cancelled = request.getString("login_id")
                    complete(Result.success(JSONObject()))
                }
                else -> complete(Result.success(metadata()))
            }
        }
    model.startSignIn()
    model.cancelLogin()
    finish(Result.success(login()))
    check(cancelled == "test-only" && model.login == null && !model.busy)
}

private fun recoveredCancellationCanBeRetried() {
    var attempts = 0
    val model =
        AtlasAIAccountsModel("recovered-only") { request, complete ->
            if (request.getString("action") == "cancel_chatgpt") {
                check(request.getString("login_id") == "recovered-only")
                attempts += 1
                if (attempts == 1) {
                    complete(Result.failure(AuthFailure("server", "Try again")))
                } else {
                    complete(Result.success(JSONObject()))
                }
            } else {
                complete(Result.success(metadata()))
            }
        }
    model.load()
    check(model.pendingLoginId == "recovered-only" && model.message == "Try again")
    model.startSignIn()
    check(attempts == 2 && model.pendingLoginId == null && model.message == null)
}

private fun terminalFailureStopsPolling(kind: String) {
    val actions = mutableListOf<String>()
    val model =
        AtlasAIAccountsModel { request, complete ->
            val action = request.getString("action")
            actions.add(action)
            if (action == "start_chatgpt") {
                complete(Result.success(login()))
            } else {
                complete(Result.failure(AuthFailure(kind, "Sign-in failed")))
            }
        }
    model.startSignIn()
    Handler(Looper.getMainLooper()).post {
        check(actions == listOf("start_chatgpt", "poll_chatgpt"))
        check(model.login == null && model.message == "Sign-in failed" && !model.busy)
    }
}

private fun signOutQueuesBehindAccountWork(context: Context) {
    val storage = AtlasSecureStorage(context)
    check(storage.load("session") == null)
    storage.save("pending", JSONObject().put("fixture", "preview-only"))
    val authentication = AtlasAuthentication(context)
    var accountComplete = false
    authentication.listener = {
        if (!authentication.busy) {
            check(accountComplete && storage.load("pending") == null)
            authentication.close()
        }
    }
    authentication.aiAccounts(JSONObject().put("action", "list")) {
        check((it.exceptionOrNull() as? AuthFailure)?.kind == "sign_in_required")
        accountComplete = true
    }
    authentication.signOut()
}
