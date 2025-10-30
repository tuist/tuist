export default {
  mounted() {
    // Get the user's timezone
    const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone;

    // Send the timezone to the LiveView
    this.pushEvent("set-timezone", { timezone: timezone });
  }
};
