// Get user timezone for LiveView and store in cookie
export function getUserTimezone() {
  const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone;
  // Store in cookie for server-side access on refresh
  document.cookie = `user_timezone=${encodeURIComponent(timezone)}; path=/; SameSite=Lax; max-age=31536000`; // 1 year
  return timezone;
}
