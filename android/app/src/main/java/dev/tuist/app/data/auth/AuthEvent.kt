package dev.tuist.app.data.auth

sealed interface AuthEvent {
    data object SessionExpired : AuthEvent
}
