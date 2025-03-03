export async function setupCookieConsent() {
  try {
    await import("vanilla-cookieconsent/dist/cookieconsent.css");
    const CookieConsent = await import("vanilla-cookieconsent");
    CookieConsent.run({
      cookie: {
        useLocalStorage: true,
      },
      guiOptions: {
        consentModal: {
          layout: "box",
          position: "bottom left",
          equalWeightButtons: true,
          flipButtons: false,
        },
        preferencesModal: {
          layout: "box",
          position: "right",
          equalWeightButtons: true,
          flipButtons: false,
        },
      },
      categories: {
        necessary: {
          readOnly: true,
        },
        functionality: {},
        analytics: {},
      },
      language: {
        default: "en",
        autoDetect: "browser",
        translations: {
          en: {
            consentModal: {
              title: "We use cookies to improve your experience",
              description:
                "At Tuist, we use cookies to enhance functionality, analyze site usage, and provide relevant marketing content. You can choose to accept all cookies or manage your preferences.",
              acceptAllBtn: "Accept all",
              acceptNecessaryBtn: "Only necessary",
              showPreferencesBtn: "Manage preferences",
              footer: '<a href="/privacy">Privacy Policy</a>\n<a href="/terms">Terms and Conditions</a>',
            },
            preferencesModal: {
              title: "Cookie Preferences",
              acceptAllBtn: "Accept all",
              acceptNecessaryBtn: "Only necessary",
              savePreferencesBtn: "Save preferences",
              closeIconLabel: "Close modal",
              serviceCounterLabel: "Service|Services",
              sections: [
                {
                  title: "About Cookies",
                  description:
                    "Cookies help us improve your browsing experience, personalize content, and measure website traffic. You can adjust your settings below to control how we use cookies.",
                },
                {
                  title: 'Strictly Necessary Cookies <span class="pm__badge">Always Enabled</span>',
                  description:
                    "These cookies are essential for the website to function properly. They ensure security, authentication, and basic functionality, and cannot be disabled.",
                  linkedCategory: "necessary",
                },
                {
                  title: "Functionality Cookies",
                  description:
                    "These cookies enable enhanced functionality, such as remembering your preferences or enabling interactive features.",
                  linkedCategory: "functionality",
                },
                {
                  title: "Analytics Cookies",
                  description:
                    "These cookies help us understand how users interact with our website by collecting and reporting information anonymously.",
                  linkedCategory: "analytics",
                },
                {
                  title: "Marketing Cookies",
                  description:
                    "These cookies allow us to provide relevant marketing content based on your interests and browsing behavior.",
                  linkedCategory: "marketing",
                },
                {
                  title: "More Information",
                  description:
                    'For further details on our cookie policy, please <a class="cc__link" href="#contact">contact us</a>.',
                },
              ],
            },
          },
        },
      },
    });
  } catch {
    console.error(
      "Couldn't initialize the cookie consent banner. It could be due to ad blockers preventing the module from loading.",
    );
  }
}
