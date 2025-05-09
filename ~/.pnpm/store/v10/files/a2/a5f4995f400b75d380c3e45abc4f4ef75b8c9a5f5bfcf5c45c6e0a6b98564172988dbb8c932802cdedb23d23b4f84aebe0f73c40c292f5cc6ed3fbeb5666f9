const appleItunesApp = {
  name: "apple-itunes-app",
  key: "name",
  color: "#FFB30",
  tags: "other",
  description: "Used to configure how iOS handles links to the App Store and enables various behaviors within a web app when it is launched from the home screen.",
  tips: [
    {
      title: "Include Essential Values",
      description: 'Ensure that you include the required values such as "app-id" to specify the unique identifier of your iOS app.'
    },
    {
      title: "Define Behavior",
      description: 'Use the "app-argument" parameter to set up custom behavior within your web app when it is opened from the home screen.'
    }
  ],
  examples: [
    {
      value: "app-id=123456789",
      description: 'Specifies the "apple-itunes-app" meta tag with "app-id" parameter set to the unique identifier of an iOS app.'
    },
    {
      value: "app-argument=custom-behavior",
      description: 'Defines the "apple-itunes-app" meta tag with "app-argument" parameter to enable custom behavior within a web app launched from the home screen.'
    }
  ],
  documentation: [
    "https://developer.apple.com/library/archive/documentation/AppleApplications/Reference/SafariWebContent/PromotingAppswithAppBanners/PromotingAppswithAppBanners.html"
  ]
};

const appleMobileWebAppCapable = {
  name: "apple-mobile-web-app-capable",
  key: "name",
  color: "#FF8C00",
  tags: "pwa",
  description: 'Specifies whether a web application can run in full-screen mode on iOS devices. When set to "yes", the web app can be launched from the home screen and appears without Safari browser UI.',
  tips: [
    {
      title: 'Set to "yes" for Progressive Web Apps (PWA)',
      description: 'If you are building a PWA and want to provide users with a native-like app experience on iOS, set the "apple-mobile-web-app-capable" meta tag to "yes".'
    },
    {
      title: "Ensure Compatibility with Safari",
      description: "Keep in mind that this meta tag is specific to iOS and will not have any effect on other operating systems or browsers."
    }
  ],
  examples: [
    {
      value: "yes",
      description: "Enables the web app to run in full-screen mode on iOS devices, providing a native-like app experience for users."
    },
    {
      value: "no",
      description: "Disables the full-screen mode for the web app on iOS devices, causing it to open in Safari with browser UI."
    }
  ],
  documentation: [
    "https://developer.apple.com/library/archive/documentation/AppleApplications/Reference/SafariHTMLRef/Articles/MetaTags.html"
  ]
};

const appleMobileWebAppStatusBarStyle = {
  name: "apple-mobile-web-app-status-bar-style",
  key: "name",
  color: "#FF9100",
  tags: "pwa",
  description: "Specifies the style of the status bar for a progressive web app (PWA) displayed on iOS devices.",
  tips: [
    {
      title: "Choose a Suitable Style",
      description: "Consider the appearance and branding of your PWA when selecting the status bar style. Make sure it complements the overall design and enhances the user experience."
    },
    {
      title: "Test Across Devices",
      description: "Test your PWA on different iOS devices to ensure the status bar style looks consistent and visually appealing."
    }
  ],
  examples: [
    {
      value: "default",
      description: "Specifies the default status bar style, which displays a black bar with a white foreground color."
    },
    {
      value: "black",
      description: "Sets the status bar style to black, displaying a black bar with a white foreground color."
    },
    {
      value: "black-translucent",
      description: "Sets the status bar style to black-translucent, making the status bar transparent with white foreground content overlaying it."
    }
  ],
  documentation: [
    "https://developer.apple.com/documentation/webkit/dark_mode_support_in_web_content",
    "https://developer.apple.com/documentation/webkit/supporting_associated_domains"
  ]
};

const appleMobileWebAppTitle = {
  name: "apple-mobile-web-app-title",
  key: "name",
  color: "#FFA500",
  tags: "browser",
  description: "Specifies the title of a web application when it is saved to the home screen on an Apple device.",
  tips: [
    {
      title: "Keep it Short and Clear",
      description: "Choose a concise and descriptive title for your web application to provide users with a clear understanding of its purpose."
    }
  ],
  examples: [
    {
      value: "My App",
      description: 'Sets the "apple-mobile-web-app-title" meta tag to display "My App" as the title of the web application on the home screen of an Apple device.'
    },
    {
      value: "My Awesome App",
      description: 'Specifies the "apple-mobile-web-app-title" meta tag with the value "My Awesome App" to set the title of the web application on the home screen of an Apple device.'
    }
  ],
  documentation: [
    "https://developer.apple.com/documentation/webkit/delivering_app-like_user_experiences_on_the_web?language=javascript#add_the_web_app_manifest"
  ]
};

const applicationName = {
  name: "application-name",
  key: "name",
  color: "#FF96A8",
  tags: "browser",
  description: "Specifies the name of the web application or site.",
  tips: [
    {
      title: "Keep it Short and Descriptive",
      description: "Choose a concise and descriptive name for your web application or site that accurately reflects its purpose."
    },
    {
      title: "Avoid Keyword Stuffing",
      description: "Don't use this meta tag as an opportunity to stuff in keywords. Instead, focus on providing a clear and meaningful name for your application or site."
    }
  ],
  examples: [
    {
      value: "My Cool App",
      description: 'Specifies the "application-name" meta tag with the name "My Cool App" for a web application or site.'
    },
    {
      value: "Awesome Web",
      description: 'Defines the "application-name" meta tag with the name "Awesome Web" for a web application or site.'
    }
  ],
  documentation: [
    "https://developer.mozilla.org/en-US/docs/Web/HTML/Element/meta/name#attr-application-name",
    "https://developer.chrome.com/docs/extensions/mv2/manifest/manifest-intro/#name"
  ]
};

const articleAuthor = {
  name: "article:author",
  key: "property",
  color: "#1890FF",
  tags: "social-share",
  description: "Specifies the author of an article or a blog post for social media sharing. This meta tag is used by platforms like Facebook and Twitter to display the author of the article when the content is shared on their platforms.",
  tips: [
    {
      title: "Include Author Name",
      description: "Make sure to include the full name of the author in the value of the meta tag to ensure proper attribution."
    },
    {
      title: "Use Personal Profile URL",
      description: "Consider including the URL of the author's personal profile page or their website in the value of the meta tag to provide a direct link to their work."
    }
  ],
  examples: [
    {
      value: "John Doe",
      description: `Specifies the "article:author" meta tag with the author's name to indicate that John Doe is the author of the article or blog post.`
    },
    {
      value: "John Doe, https://johndoe.com",
      description: `Specifies the "article:author" meta tag with the author's name and their personal website URL to provide attribution and a direct link to their work.`
    }
  ],
  documentation: [
    "https://developers.facebook.com/docs/sharing/webmasters#markup",
    "https://developer.twitter.com/en/docs/twitter-for-websites/cards/guides/getting-started"
  ]
};

const articleExpirationTime = {
  name: "article:expiration_time",
  key: "property",
  color: "#FF69B4",
  tags: "social-share",
  description: "Specifies the date and time after which the article is no longer considered relevant or up-to-date.",
  tips: [
    {
      title: "Format the Date and Time",
      description: "Use the ISO 8601 format (YYYY-MM-DDThh:mm:ssZ) to specify the expiration date and time."
    },
    {
      title: "Consider Time Zones",
      description: "Make sure to specify the time zone when defining the expiration time to avoid confusion."
    }
  ],
  examples: [
    {
      value: "2022-12-31T23:59:59Z",
      description: 'Sets the "article:expiration_time" meta tag to December 31, 2022, at 23:59:59 UTC.'
    },
    {
      value: "2023-06-15T12:00:00-07:00",
      description: 'Defines the "article:expiration_time" meta tag to June 15, 2023, at 12:00:00 in the GMT-7 time zone.'
    }
  ],
  documentation: [
    "https://ogp.me/#structured",
    "https://developer.twitter.com/en/docs/twitter-for-websites/cards/overview/summary-card-with-large-image"
  ]
};

const articleModifiedTime = {
  name: "article:modified_time",
  key: "property",
  color: "#50BDBD",
  tags: "social-share",
  description: "Specifies the time when the article was last modified. This meta tag is used by social media platforms to display the updated timestamp of an article when it is shared.",
  tips: [
    {
      title: "Include the Correct Time Format",
      description: "Make sure to include the timestamp in the ISO 8601 format (YYYY-MM-DDThh:mm:ssZ) to ensure compatibility with various platforms."
    },
    {
      title: "Update After Content Changes",
      description: 'Update the "article:modified_time" meta tag whenever the content of the article is modified to ensure accurate display of the updated timestamp.'
    }
  ],
  examples: [
    {
      value: "2022-01-12T13:30:45Z",
      description: 'Specifies the "article:modified_time" meta tag with the timestamp of January 12, 2022, at 13:30:45 UTC.'
    },
    {
      value: "2021-11-05T09:15:00Z",
      description: 'Defines the "article:modified_time" meta tag with the timestamp of November 5, 2021, at 09:15:00 UTC.'
    }
  ],
  documentation: [
    "https://ogp.me/",
    "https://developers.facebook.com/docs/sharing/webmasters/",
    "https://dev.twitter.com/cards/types"
  ]
};

const articlePublishedTime = {
  name: "article:published_time",
  key: "property",
  color: "#FF8C00",
  tags: ["seo", "social-share"],
  description: "Specifies the date and time when an article was published.",
  tips: [
    {
      title: "Use ISO 8601 Format",
      description: "When specifying the value for the article:published_time meta tag, use the ISO 8601 date and time format (YYYY-MM-DDTHH:MM:SSZ). This format ensures compatibility and consistency across different platforms and systems."
    },
    {
      title: "Keep the Published Time Accurate",
      description: "Ensure that the value provided for the article:published_time meta tag accurately reflects the actual date and time when the article was published. This information is important for search engines and social media platforms to display and order content correctly."
    }
  ],
  examples: [
    {
      value: "2022-01-15T10:30:00Z",
      description: 'Specifies the "article:published_time" meta tag with the value set to January 15, 2022, at 10:30:00 AM UTC.'
    }
  ],
  documentation: [
    "https://ogp.me/",
    "https://developers.facebook.com/docs/sharing/webmasters/",
    "https://developer.twitter.com/en/docs/twitter-for-websites/cards/overview/summary"
  ]
};

const articleSection = {
  name: "article:section",
  key: "property",
  color: "#FF9900",
  tags: "seo",
  description: "Specifies the section or category of an article for search engines and social media platforms. It helps organize and classify content, improving its visibility in relevant search results.",
  tips: [
    {
      title: "Choose Relevant Sections",
      description: "Select appropriate and relevant sections or categories for your articles to help search engines and users understand the context of your content."
    },
    {
      title: "Be Specific",
      description: "Use specific section names that accurately reflect the topic or theme of your articles. Avoid generic or vague section names that may not provide meaningful information."
    },
    {
      title: "Consistency",
      description: 'Ensure consistency in the usage of "article:section" meta tag across your website. Use the same section names for articles within the same category or topic.'
    }
  ],
  examples: [
    {
      value: "Technology",
      description: 'Specifies the "article:section" meta tag with the value "Technology" to indicate that the article belongs to the Technology section of the website.'
    },
    {
      value: "Sports",
      description: 'Defines the "article:section" meta tag with the value "Sports" to categorize the article under the Sports section.'
    }
  ],
  documentation: [
    "https://moz.com/learn/seo/meta-description",
    "https://developers.facebook.com/docs/sharing/webmasters#markup",
    "https://ogp.me/",
    "https://developer.twitter.com/en/docs/twitter-for-websites/cards/guides/getting-started"
  ]
};

const articleTag = {
  name: "article:tag",
  key: "property",
  color: "#FFA700",
  tags: "social-share",
  type: "open-graph-protocol",
  description: "Specifies one or more tags or keywords that are relevant to the content of an article or blog post. These tags can be used for categorizing and organizing articles in search results and social media platforms.",
  tips: [
    {
      title: "Use Relevant and Specific Tags",
      description: "Choose tags that accurately describe the content of the article. Avoid using generic or unrelated tags that may mislead readers or search engines."
    },
    {
      title: "Include Properly Capitalized Tags",
      description: "Ensure that the tags are capitalized correctly and consistently. This can improve the readability and presentation of the tags on social media platforms."
    },
    {
      title: "Limit the Number of Tags",
      description: "While the article:tag meta allows multiple tags, it is recommended to limit the number of tags to a reasonable amount. Too many tags can make the content appear spammy and may have a negative impact on SEO."
    }
  ],
  examples: [
    {
      value: "web development",
      description: 'Specifies the "article:tag" meta tag with the tag "web development" for an article about web development. This tag can be used by social media platforms to categorize and display the article.'
    },
    {
      value: "technology, artificial intelligence",
      description: 'Defines the "article:tag" meta tag with multiple tags "technology" and "artificial intelligence" for an article related to these topics. These tags can provide additional context and improve discoverability of the article.'
    }
  ],
  documentation: [
    "https://ogp.me/#type_article"
  ]
};

const author = {
  name: "author",
  key: "name",
  color: "#FF4081",
  tags: ["seo", "other"],
  description: "Specifies the author of the web page or content.",
  tips: [
    {
      title: "Use Real Names",
      description: "Use the real name of the author to provide transparency and trustworthiness to the content."
    },
    {
      title: "Avoid Keywords",
      description: "Do not use keywords in the author meta tag. It is meant to represent a person, not for SEO purposes."
    }
  ],
  examples: [
    {
      value: "John Doe",
      description: "Specifies the author of the web page as John Doe."
    },
    {
      value: "Jane Smith",
      description: "Specifies the author of the web page as Jane Smith."
    }
  ],
  documentation: []
};

const bookAuthor = {
  name: "book:author",
  key: "name",
  color: "#FF7F50",
  tags: "other",
  description: "Specifies the author of a book or literary work. This meta tag is commonly used in web pages that provide information about books or have a book-related focus.",
  tips: [
    {
      title: "Provide Accurate Author Information",
      description: 'Ensure that the author name provided in the "book:author" meta tag is accurate and matches the actual author of the book or literary work.'
    },
    {
      title: "Use Schema.org Markup Instead",
      description: "Consider using Schema.org markup for book-related information, including author details. This can provide more structured data to search engines."
    }
  ],
  examples: [
    {
      value: "John Doe",
      description: 'Specifies the "book:author" meta tag with the name "John Doe" as the author of the book.'
    },
    {
      value: "Jane Smith",
      description: 'Defines the "book:author" meta tag with the name "Jane Smith" as the author of the book.'
    }
  ],
  documentation: [
    "https://schema.org/Person",
    "https://developers.google.com/search/docs/data-types/book"
  ]
};

const bookIsbn = {
  name: "book:isbn",
  key: "property",
  color: "#FF99CC",
  tags: "seo",
  description: "Provides the International Standard Book Number (ISBN) for a book page on a website. ISBNs are unique numeric identifiers used to identify books globally.",
  tips: [
    {
      title: "Include Accurate ISBN",
      description: "Make sure to include the correct ISBN for the book. Incorrect or missing ISBNs can lead to confusion and affect the book's discoverability."
    },
    {
      title: "Use Valid ISBN Format",
      description: "Ensure that the ISBN is in the correct format. ISBNs can be either 10 or 13 digits long and may include hyphens. Verify the formatting guidelines provided by ISBN registration authorities."
    }
  ],
  examples: [
    {
      value: "978-0-306-40615-7",
      description: 'Specifies the "book:isbn" meta tag with the ISBN 978-0-306-40615-7 for a book page, providing a unique identifier for the book.'
    },
    {
      value: "0-201-61622-X",
      description: 'Defines the "book:isbn" meta tag with the ISBN 0-201-61622-X for a book page, using the older 10-digit format.'
    }
  ],
  documentation: [
    "https://moz.com/learn/seo/meta-tags",
    "https://www.isbn-international.org/"
  ]
};

const bookReleaseDate = {
  name: "book:release_date",
  key: "property",
  color: "#FF00FF",
  tags: "other",
  description: "Specifies the release date of a book for search engines and social media platforms. It helps search engines understand the publishing timeline of a book and enable enhanced search features for users interested in specific release dates.",
  tips: [],
  examples: [
    {
      value: "2022-10-20",
      description: `Specifies the "book:release_date" meta tag with the release date of the book as October 20, 2022. This allows search engines and social media platforms to display the book's release date in search results and other relevant features.`
    },
    {
      value: "2023-01-01",
      description: 'Defines the "book:release_date" meta tag with the release date of the book as January 1, 2023. This provides accurate information to search engines and social media platforms for displaying release date-related features.'
    }
  ],
  documentation: [
    "https://developers.google.com/search/docs/data-types/book",
    "https://twitter.com/opengraph",
    "https://ogp.me/"
  ]
};

const bookTag = {
  name: "book:tag",
  key: "property",
  color: "#FF6699",
  tags: "seo",
  description: "Specifies the keywords or tags associated with a book or publication.",
  tips: [
    {
      title: "Choose Relevant Tags",
      description: "Select tags that accurately represent the content of the book and are relevant to potential readers."
    },
    {
      title: "Use Specific Tags",
      description: "Avoid using generic tags and instead use specific keywords that describe the book in more detail."
    }
  ],
  examples: [
    {
      value: "fiction, mystery, thriller",
      description: 'Specifies the "book:tag" meta tag with tags for a fictional book belonging to the mystery and thriller genres.'
    },
    {
      value: "non-fiction, self-help, personal development",
      description: 'Defines the "book:tag" meta tag with tags for a non-fictional book focused on self-help and personal development.'
    }
  ],
  documentation: [
    "https://developers.google.com/search/docs/data-types/book",
    "https://schema.org/keywords"
  ]
};

const charset = {
  key: "charset",
  name: "charset",
  type: "standard",
  color: "#FFA500",
  tags: ["browser"],
  description: "Defines the character encoding for a web page. Character encoding specifies how characters are represented digitally, ensuring proper display of text and content on the page.",
  tips: [
    {
      title: "Use UTF-8",
      description: "The most widely supported and recommended character encoding for web pages is UTF-8."
    },
    {
      title: "Declare in HTML",
      description: 'Ensure that the "charset" meta tag is included in the head section of your HTML document.'
    },
    {
      title: "Place It Early",
      description: 'To ensure proper interpretation of characters by the browser, place the "charset" meta tag as one of the first tags in the head section.'
    }
  ],
  examples: [
    {
      value: "UTF-8",
      description: 'Specifies the "charset" meta tag with the UTF-8 character encoding for a web page, ensuring compatibility with a wide range of characters.'
    },
    {
      value: "ISO-8859-1",
      description: 'Defines the "charset" meta tag with the ISO-8859-1 character encoding for a web page, which is less common but may be necessary for specific cases.'
    }
  ],
  documentation: [
    "https://developer.mozilla.org/en-US/docs/Web/HTML/Element/meta#attr-charset",
    "https://www.w3.org/International/articles/definitions-characters/"
  ]
};

const colorScheme = {
  name: "color-scheme",
  key: "name",
  color: "#FFD700",
  tags: "browser",
  description: "Specifies the preferred color scheme for rendering a web page.",
  tips: [
    {
      title: "Set a Preferred Color Scheme",
      description: 'Use the "color-scheme" meta tag to specify the preferred color scheme for your web page. This helps ensure a consistent user experience across different devices and operating systems.'
    },
    {
      title: "Fallback to Default",
      description: "If the preferred color scheme is not supported or not specified, the browser will use the default color scheme."
    }
  ],
  examples: [
    {
      value: "light",
      description: 'Specifies the "color-scheme" meta tag with a preferred color scheme of light. This is suitable for web pages with a light background.'
    },
    {
      value: "dark",
      description: 'Specifies the "color-scheme" meta tag with a preferred color scheme of dark. This is suitable for web pages with a dark background.'
    },
    {
      value: "light dark",
      description: 'Specifies the "color-scheme" meta tag with multiple preferred color schemes, indicating support for both light and dark backgrounds.'
    }
  ],
  documentation: [
    "https://developer.mozilla.org/en-US/docs/Web/HTML/Element/meta/name/color-scheme",
    "https://css-tricks.com/dark-modes-with-css/"
  ]
};

const contentSecurityPolicy = {
  name: "content-security-policy",
  key: "http-equiv",
  color: "#FF1493",
  tags: "security",
  description: "Specifies the content security policy (CSP) for a web page. CSP is used to mitigate the risk of cross-site scripting (XSS) attacks by specifying which sources or types of content are allowed to be loaded or executed on a web page.",
  tips: [
    {
      title: "Implement a Strict CSP",
      description: "Consider implementing a strict CSP that only allows trusted sources to load content. This can help prevent XSS attacks and protect your website users."
    },
    {
      title: "Regularly Review and Update CSP",
      description: "Regularly review and update the content security policy to ensure it covers all necessary sources and provides adequate protection against potential vulnerabilities."
    }
  ],
  examples: [
    {
      value: "default-src 'self'",
      description: "Specifies that content should only be loaded from the same origin as the web page. This restricts content from external sources and provides a basic level of protection."
    },
    {
      value: "script-src 'self' 'unsafe-inline'",
      description: "Allows inline JavaScript to be executed on the web page. Use with caution, as it may introduce security risks."
    }
  ],
  documentation: [
    "https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy",
    "https://content-security-policy.com/"
  ]
};

const contentType = {
  name: "content-type",
  key: "http-equiv",
  color: "#FF8C00",
  tags: "browser",
  description: "Specifies the character encoding and media type of a web page. It helps the browser understand how to interpret the content of the page.",
  tips: [
    {
      title: "Specify UTF-8 Encoding",
      description: 'Set the "content-type" meta tag with "charset=UTF-8" to ensure proper display of characters on the page.'
    },
    {
      title: "Choose the Correct Media Type",
      description: 'Select the appropriate media type based on the nature of your content. Common examples include "text/html" for HTML pages and "application/javascript" for JavaScript files.'
    }
  ],
  examples: [
    {
      value: "text/html; charset=UTF-8",
      description: 'Sets the "content-type" meta tag with the media type "text/html" and the UTF-8 character encoding.'
    },
    {
      value: "application/javascript",
      description: 'Defines the "content-type" meta tag with the media type "application/javascript" for JavaScript files.'
    }
  ],
  documentation: [
    "https://developer.mozilla.org/en-US/docs/Web/HTML/Element/meta/http-equiv#attr-http-equiv-content-type",
    "https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Type"
  ]
};

const creator = {
  name: "creator",
  key: "name",
  color: "#1E88E5",
  tags: "other",
  description: "Specifies the author or creator of the web page or content. It is used to provide attribution and credit for the work.",
  tips: [
    {
      title: "Use Real People or Organization Names",
      description: 'When using the "creator" meta tag, provide the actual name of the individual or organization responsible for the page or content. This helps establish credibility and provides proper attribution.'
    },
    {
      title: "Don't Overuse or Misuse",
      description: 'Avoid using the "creator" meta tag excessively or for misleading purposes. It should accurately reflect the true creator of the content.'
    }
  ],
  examples: [
    {
      value: "John Doe",
      description: 'Specifies the "creator" meta tag with the name "John Doe" as the author or creator of the web page.'
    },
    {
      value: "Example Corp",
      description: 'Sets the "creator" meta tag to "Example Corp" to indicate that the organization is responsible for the web page or content.'
    }
  ],
  documentation: [
    "https://developer.mozilla.org/en-US/docs/Web/HTML/Element/meta/name"
  ]
};

const defaultStyle = {
  name: "default-style",
  key: "http-equiv",
  parameters: [
    "content-type"
  ],
  type: "standard",
  color: "#FFB300",
  tags: "browser",
  description: 'Specifies the preferred default style sheet for the web page. The "default-style" meta tag is used by older versions of Internet Explorer to set the default style for the page.',
  tips: [
    {
      title: "Specify a Default Style Sheet",
      description: 'Set the preferred default style sheet for the web page using the "default-style" meta tag. This can help ensure that the page is displayed consistently across different browsers.'
    }
  ],
  examples: [
    {
      value: "text/html; charset=utf-8",
      description: 'Specifies the default style sheet for the web page as "text/html; charset=utf-8", which is the recommended default style.'
    }
  ],
  documentation: [
    "https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Type"
  ]
};

const description = {
  name: "description",
  key: "name",
  type: "standard",
  color: "#FF9900",
  tags: ["seo", "social-share"],
  description: "Provides a concise and accurate summary of the web page content. This meta tag is commonly used by search engines to display a preview snippet in search results and plays a crucial role in improving a page's visibility and click-through rate (CTR).",
  tips: [
    {
      title: "Keep it Short and Unique",
      description: "Limit the description to 150-160 characters to ensure it displays in its entirety on search engine result pages (SERPs). Avoid duplicate descriptions across pages to provide users with distinct and relevant information for each page."
    },
    {
      title: "Include Relevant Keywords",
      description: "Incorporate targeted keywords naturally within the description to enhance its relevance and increase the likelihood of appearing in search results. However, avoid keyword stuffing as it can negatively impact SEO."
    },
    {
      title: "Write Compelling and Engaging Descriptions",
      description: "Craft a concise and compelling description that entices users to click on the link. Consider highlighting unique selling points, benefits, or a call-to-action to capture user interest and improve CTR."
    },
    {
      title: "Avoid HTML Tags and Special Characters",
      description: "Do not include HTML tags, such as <strong> or <em>, in the description as they are unnecessary and may appear as plain text on the SERPs. Similarly, special characters should be avoided or properly encoded."
    }
  ],
  examples: [
    {
      value: "Discover the latest fashion trends and shop for stylish clothing and accessories at our online store. Enjoy free shipping for orders over $50!",
      description: "A description for an online fashion store, highlighting its offerings and incentives to entice users to click through to the website."
    },
    {
      value: "Learn advanced JavaScript techniques and best practices from our comprehensive online tutorials. Boost your coding skills with in-depth examples and exercises.",
      description: "A description for a website offering JavaScript tutorials, emphasizing its comprehensive content and the opportunity to enhance coding skills."
    }
  ],
  documentation: [
    "https://developer.mozilla.org/en-US/docs/Web/HTML/Element/meta/name#attr-name-description",
    "https://developers.google.com/search/docs/advanced/appearance/snippet#meta-tags",
    "https://moz.com/learn/seo/meta-description"
  ]
};

const fbAppId = {
  name: "fb:app_id",
  key: "property",
  color: "#3B5998",
  tags: "social-share",
  description: "Used to associate a Facebook App ID with a web page. This allows the web page to be integrated and interact with the associated Facebook app.",
  tips: [
    {
      title: "Create a Facebook App",
      description: 'Before using the "fb:app_id" meta tag, make sure you have created a Facebook app and obtained its corresponding ID.'
    },
    {
      title: "Integrate with Facebook APIs",
      description: 'Once the "fb:app_id" meta tag is added, you can use the Facebook JavaScript SDK or other Facebook APIs to extend the functionality of your web page and integrate it with your Facebook app.'
    }
  ],
  examples: [
    {
      value: "1234567890",
      description: 'Specifies the "fb:app_id" meta tag with the Facebook App ID "1234567890" associated with a web page.'
    }
  ],
  documentation: [
    "https://developers.facebook.com/docs/sharing/webmasters#basic"
  ]
};

const formatDetection = {
  name: "format-detection",
  key: "name",
  color: "#FFC107",
  tags: "browser",
  description: "Enables or disables automatic detection of potential phone numbers, email addresses, and addresses in a web page. This meta tag is specific to mobile browsers.",
  tips: [
    {
      title: "Enable Detection for Specific Formats",
      description: 'Add specific format values to enable automatic detection for phone numbers, email addresses, or addresses. For example, "telephone=no" disables phone number detection, while "email=no" disables email address detection.'
    },
    {
      title: "Disable Detection",
      description: 'Use "format-detection=telephone=no" meta tag to disable automatic phone number detection, "format-detection=email=no" to disable email address detection, and "format-detection=address=no" to disable address detection.'
    }
  ],
  examples: [
    {
      value: "telephone=no",
      description: "Disables automatic detection of phone numbers on a web page."
    },
    {
      value: "email=no",
      description: "Disables automatic detection of email addresses on a web page."
    },
    {
      value: "address=no",
      description: "Disables automatic detection of addresses on a web page."
    }
  ],
  documentation: [
    "https://developer.apple.com/documentation/safari_web_content/SafariHTMLRef/Articles/MetaTags.html#//apple_ref/doc/uid/TP40008193-SW27",
    "https://developer.mozilla.org/en-US/docs/Web/HTML/Element/meta/name/format-detection"
  ]
};

const generator = {
  name: "generator",
  key: "name",
  color: "#FFD700",
  tags: "browser",
  description: "Specifies the name and version of the software used to generate the web page.",
  tips: [
    {
      title: "Include Generator Meta Tag for Development Purposes",
      description: 'During development, it can be useful to include a "generator" meta tag to quickly identify the software and version used to generate the web page.'
    },
    {
      title: "Consider Removing Generator Meta Tag in Production",
      description: 'For security reasons, it is recommended to remove the "generator" meta tag in the production environment to avoid revealing sensitive information about the software stack.'
    }
  ],
  examples: [
    {
      value: "WordPress 5.8",
      description: 'Specifies the "generator" meta tag with the version of WordPress used to generate the web page.'
    },
    {
      value: "Jekyll 4.2.0",
      description: 'Defines the "generator" meta tag with the version of Jekyll used to generate the web page.'
    }
  ],
  documentation: [
    "https://developer.mozilla.org/en-US/docs/Web/HTML/Element/meta#attr-generator",
    "https://www.w3schools.com/tags/tag_meta.asp"
  ]
};

const google = {
  name: "google",
  key: "name",
  color: "#FF6400",
  tags: "seo",
  description: "Used to provide specific instructions to Google search engine for indexing and displaying web pages in search results.",
  tips: [
    {
      title: "Use with Other Meta Tags",
      description: 'Combine the "google" meta tag with other relevant meta tags, such as "robots" and "description", to optimize your site for Google search.'
    },
    {
      title: "Avoid Over-Optimization",
      description: "Avoid excessive use of targeted keywords or other manipulative techniques to optimize your site for Google search, as it may lead to penalties."
    }
  ],
  examples: [
    {
      value: "nositelinkssearchbox",
      description: "Instructs Google not to display a sitelinks search box for the web page in search results."
    },
    {
      value: "notranslate",
      description: "Prevents Google from offering translation services for the web page in search results."
    }
  ],
  documentation: [
    "https://developers.google.com/search/docs/advanced/crawling/googlebot#google-mobile-friendly-search-results",
    "https://developers.google.com/search/reference/robots_meta_tag#google-specific-instructions"
  ]
};

const googleSiteVerification = {
  name: "google-site-verification",
  key: "name",
  color: "#4CAF50",
  tags: "seo",
  type: "google",
  description: "Used to verify the ownership of a website with Google Search Console. It is an essential step for webmasters to gain access to data and settings related to their website in Google's search index.",
  tips: [
    {
      title: "Follow the Verification Process",
      description: 'After adding the "google-site-verification" meta tag to your website, follow the verification process in Google Search Console to prove that you own the website.'
    },
    {
      title: "Keep Verification Code Secure",
      description: "Ensure that your verification code remains confidential and is not shared with unauthorized individuals, as it grants access to your website's data and settings in Google Search Console."
    }
  ],
  examples: [
    {
      value: "abcdefg123456789",
      description: 'Specifies the "google-site-verification" meta tag with a unique verification code provided by Google Search Console.'
    }
  ],
  documentation: [
    "https://support.google.com/webmasters/answer/9008080?hl=en"
  ]
};

const googlebot = {
  name: "googlebot",
  key: "name",
  description: "Used to provide specific instructions to Googlebot, the web crawler used by Google for indexing and ranking web pages.",
  examples: [
    {
      value: "noimageindex",
      description: "Instructs Googlebot not to index images on the page."
    },
    {
      value: "nosnippet",
      description: "Prevents Google from generating a snippet for the page in search results."
    }
  ],
  parameters: [
    { value: "noimageindex", description: "Instructs Googlebot not to index images on the page." },
    { value: "nosnippet", description: "Prevents Google from generating a snippet for the page in search results." },
    { value: "nofollow", description: "Instructs Googlebot not to follow links on the page." },
    { value: "noindex", description: "Instructs Googlebot not to index the page." },
    { value: "max-snippet:[number]", description: "Specifies the maximum length of a snippet for the page in search results." }
  ],
  tips: [
    {
      title: "Customize Googlebot Behavior",
      description: "Use Googlebot directives to customize how Google crawls and indexes your web pages to meet your specific requirements."
    },
    {
      title: "Improve Page Visibility",
      description: 'Using directives like "noindex" and "nofollow" can help improve the visibility and search ranking of your pages.'
    }
  ],
  documentation: [
    "https://developers.google.com/search/reference/robots_meta_tag",
    "https://developers.google.com/search/docs/advanced/crawling/control-crawl-index"
  ],
  importance: "recommended",
  tags: "seo"
};

const googlebotNews = {
  name: "googlebot-news",
  key: "name",
  color: "#FFAB00",
  tags: "seo",
  description: "Used to control the behavior of Google News crawler on a web page. It allows developers to specify directives that influence indexing, following links, and other interactions specifically for Google News.",
  tips: [
    {
      title: "Follow Google News Guidelines",
      description: "Refer to Google News Publisher Center guidelines to ensure that your web page meets the requirements and best practices for Google News indexing and visibility."
    },
    {
      title: "Optimize for Search Visibility",
      description: 'Use "news_keywords" meta tag in conjunction with "googlebot-news" to provide relevant keywords for better search visibility within Google News search results.'
    }
  ],
  examples: [
    {
      value: "noindex",
      description: "Instructs Google News crawler not to index the page within Google News."
    },
    {
      value: "max-snippet:50, max-image-preview:large",
      description: "Sets the maximum length of the page snippet to 50 characters and allows Google to display larger image previews in search results for the page."
    }
  ],
  documentation: [
    "https://developers.google.com/search/docs/advanced/robots/robots_meta_tag_news"
  ]
};

const keywords = {
  name: "keywords",
  key: "name",
  color: "#FFC107",
  tags: "seo",
  description: "Specifies the keywords or phrases that best describe the content of a web page. Keywords meta tag used to be widely used for SEO purposes, but its importance has decreased over time.",
  tips: [
    {
      title: "No Longer Used for SEO",
      description: 'The "keywords" meta tag is no longer used by Google for SEO purposes, but it may still be used by other search engines.'
    }
  ],
  examples: [
    {
      value: "web development, JavaScript, SEO",
      description: 'Specifies the "keywords" meta tag with keywords relevant to a web development article focused on JavaScript and SEO.'
    },
    {
      value: "ecommerce, online shopping, product reviews",
      description: 'Defines the "keywords" meta tag with keywords related to an online shopping website specializing in product reviews.'
    }
  ],
  documentation: [
    "https://moz.com/learn/seo/meta-description",
    "https://developers.google.com/search/docs/beginner/seo-starter-guide#meta-tags"
  ]
};

const mobileWebAppCapable = {
  name: "mobile-web-app-capable",
  key: "name",
  description: "Specifies whether a web application should run in full-screen mode as a standalone web application on mobile devices.",
  color: "#00C2FF",
  tags: "pwa",
  tips: [
    {
      title: "Use with PWA",
      description: "This meta tag is commonly used in Progressive Web Applications (PWAs) to enhance user experience by allowing the web application to run in full-screen mode on mobile devices."
    },
    {
      title: "Keep Appropriate Fallback",
      description: "Ensure that your web application has an appropriate fallback for devices that do not support full-screen mode. This can be achieved by using responsive design techniques to provide a consistent experience."
    }
  ],
  examples: [
    {
      value: "yes",
      description: "Enables the web application to run in full-screen mode on supported mobile devices."
    },
    {
      value: "no",
      description: "Disables full-screen mode for the web application on mobile devices."
    }
  ],
  documentation: [
    "https://developer.mozilla.org/en-US/docs/Web/Manifest",
    "https://developers.google.com/web/fundamentals/web-app-manifest/"
  ]
};

const msapplicationConfig = {
  name: "msapplication-config",
  key: "name",
  color: "#2D89EF",
  tags: "browser",
  description: "Specifies the URL of an XML file that contains tile and icon definitions for Microsoft applications. This meta tag is specific to Internet Explorer and Microsoft Edge browsers.",
  tips: [
    {
      title: "Create an XML file",
      description: 'To use the "msapplication-config" meta tag, you need to create an XML file that defines the tiles and icons for Microsoft applications. Refer to the documentation for the XML schema and required elements.'
    },
    {
      title: "Provide multiple tile sizes",
      description: "To ensure compatibility across different devices and resolutions, provide multiple tile sizes in the XML file. This allows Microsoft applications to choose the most appropriate tile for the user's device."
    }
  ],
  examples: [
    {
      value: "/path/to/tile.xml",
      description: 'Specifies the "msapplication-config" meta tag with the URL "/path/to/tile.xml", which contains the tile and icon definitions for Microsoft applications.'
    }
  ],
  documentation: [
    "https://docs.microsoft.com/en-us/previous-versions//bb250496(v=vs.85)"
  ]
};

const msapplicationTileColor = {
  name: "msapplication-TileColor",
  key: "name",
  color: "#476AFF",
  tags: "browser",
  description: "Specifies the background color of the tile on the Windows Start Menu or the Microsoft Edge pinned sites",
  tips: [
    {
      title: "Choose the right color",
      description: "Select a color that represents your website or brand identity to make your tile stand out on the Windows Start Menu or Microsoft Edge pinned sites."
    },
    {
      title: "Consider accessibility",
      description: 'Ensure that the color you choose for "msapplication-TileColor" meets accessibility guidelines, making it easily distinguishable for users who may have visual impairments.'
    }
  ],
  examples: [
    {
      value: "#FF0000",
      description: 'Sets the "msapplication-TileColor" meta tag to a red color for the tile on the Windows Start Menu or Microsoft Edge pinned sites.'
    },
    {
      value: "#00FF00",
      description: 'Defines the "msapplication-TileColor" meta tag to a green color for the tile on the Windows Start Menu or Microsoft Edge pinned sites.'
    }
  ],
  documentation: [
    "https://developer.mozilla.org/en-US/docs/Web/HTML/Element/meta/name#attr-msapplication-tilecolor",
    "https://docs.microsoft.com/en-us/previous-versions/windows/internet-explorer/ie-developer/samples/dn455106(v=vs.85)"
  ]
};

const msapplicationTileImage = {
  name: "msapplication-TileImage",
  key: "name",
  color: "#FFB80C",
  tags: "browser",
  description: "Specifies the URL of an image to be used as the tile image for a web application in the Microsoft Windows Start menu or on the taskbar.",
  tips: [
    {
      title: "Choose an Iconic Image",
      description: "Select an image that is easily recognizable and represents your web application well to attract users on the Windows platform."
    },
    {
      title: "Use PNG Format",
      description: "Prefer using PNG format for the tile image as it supports transparency and ensures optimal visual quality."
    }
  ],
  examples: [
    {
      value: "images/start-tile.png",
      description: 'Specifies the "msapplication-TileImage" meta tag with the URL of an image "images/start-tile.png" to be used as the tile image for the web application in Windows Start menu or taskbar.'
    }
  ],
  documentation: [
    "https://docs.microsoft.com/en-us/previous-versions/windows/internet-explorer/ie-developer/platform-apis/dn455106(v=vs.85)"
  ]
};

const ogAudio = {
  name: "og:audio",
  key: "property",
  color: "#FF6384",
  tags: "social-share",
  description: "Specifies the URL to an audio file to be associated with the webpage when shared on social media platforms that support the Open Graph protocol.",
  tips: [
    {
      title: "Use High-Quality Audio",
      description: "To provide the best user experience, use high-quality audio files that are optimized for web playback."
    },
    {
      title: "Include Audio Metadata",
      description: "When specifying the URL to the audio file, also include relevant metadata, such as the title, artist, and album, to enhance the shareability and discoverability of the audio content."
    }
  ],
  examples: [
    {
      value: "https://example.com/audio.mp3",
      description: 'Specifies the "og:audio" meta tag with the URL to an MP3 audio file for the associated webpage.'
    },
    {
      value: "https://example.com/audio.wav",
      description: 'Defines the "og:audio" meta tag with the URL to a WAV audio file for the associated webpage.'
    }
  ],
  documentation: [
    "https://ogp.me/#type_music.song",
    "https://developers.facebook.com/docs/marketing-apis/open-graph"
  ]
};

const ogAudioSecureUrl = {
  name: "og:audio:secure_url",
  key: "property",
  color: "#FF8C00",
  tags: ["social-share", "seo", "other"],
  description: "Specifies the secure URL of an audio file to be associated with the web page when shared on social media platforms that support the Open Graph Protocol.",
  tips: [
    {
      title: "Use HTTPS",
      description: "Ensure that the URL provided is served over HTTPS to maintain data security and compatibility with platforms that enforce secure connections."
    },
    {
      title: "Provide High-Quality Audio",
      description: "Use high-quality audio files to enhance the user experience when the web page is shared on social media platforms."
    }
  ],
  examples: [
    {
      value: "https://example.com/audio.mp3",
      description: "Specifies the secure URL of an MP3 audio file"
    }
  ],
  documentation: [
    "https://ogp.me/",
    "https://developers.facebook.com/docs/sharing/webmasters/"
  ]
};

const ogAudioType = {
  key: "property",
  name: "og:audio:type",
  color: "#FFB30",
  tags: "social-share",
  type: "open-graph-protocol",
  description: "Specifies the MIME type of the audio content when sharing a web page on social media platforms using Open Graph protocol.",
  tips: [
    {
      title: "Provide Accurate MIME Type",
      description: 'Ensure that the MIME type specified for the "og:audio:type" meta tag accurately reflects the format of the audio content being shared. This helps social media platforms determine how to handle the audio file.'
    }
  ],
  examples: [
    {
      value: "audio/mpeg",
      description: 'Specifies the "og:audio:type" meta tag with the MIME type "audio/mpeg" for an MP3 audio file.'
    },
    {
      value: "audio/wav",
      description: 'Specifies the "og:audio:type" meta tag with the MIME type "audio/wav" for a WAV audio file.'
    }
  ],
  documentation: [
    "https://ogp.me/"
  ]
};

const ogAudioUrl = {
  name: "og:audio:url",
  key: "property",
  tags: "social-share",
  type: "open-graph-protocol",
  color: "#AED581",
  description: "Specifies the URL of an audio file to be associated with a webpage when shared on social media platforms using Open Graph Protocol. This meta tag is used to provide a preview of the audio content and enhance the user experience when sharing the webpage.",
  tips: [
    {
      title: "Provide High-Quality Audio",
      description: "Ensure that the specified audio URL leads to a high-quality audio file to provide the best possible listening experience for users when sharing the webpage on social media platforms."
    },
    {
      title: "Use Supported Audio Formats",
      description: "Check the supported audio formats for the target social media platforms to ensure compatibility and proper rendering of the audio file preview."
    }
  ],
  examples: [
    {
      value: "https://example.com/audio/podcast.mp3",
      description: 'Specifies the "og:audio:url" meta tag with the URL of a podcast audio file to be associated with the shared webpage.'
    },
    {
      value: "https://example.com/audio/soundtrack.ogg",
      description: 'Defines the "og:audio:url" meta tag with the URL of an Ogg Vorbis audio file to be associated with the shared webpage.'
    }
  ],
  documentation: [
    "https://ogp.me/"
  ]
};

const ogDescription = {
  name: "og:description",
  key: "property",
  type: "open-graph-protocol",
  color: "#FF9800",
  tags: ["social-share"],
  description: 'The "og:description" meta tag is used in Open Graph protocol to provide a brief summary or description of the content being shared. It is often used by social media platforms when a webpage is shared, allowing users to quickly understand the context or message of the shared content.',
  tips: [
    {
      title: "Keep it concise",
      description: "The description should be short and concise, typically between 100-300 characters. This allows for better readability on social media platforms and encourages users to click on the shared link."
    },
    {
      title: "Use relevant keywords",
      description: "Include relevant keywords in the description to improve search engine optimization (SEO) and ensure that the content is properly indexed by search engines."
    },
    {
      title: "Avoid duplication",
      description: 'Each webpage should have a unique "og:description" meta tag. Avoid using the same description for multiple pages, as it can negatively impact SEO and user experience.'
    }
  ],
  examples: [
    {
      value: "Discover delicious recipes for homemade pizza!",
      description: 'Specifies the "og:description" meta tag with a description for a website that shares homemade pizza recipes.'
    },
    {
      value: "Learn how to play guitar with easy-to-follow tutorials.",
      description: 'Defines the "og:description" meta tag with a brief summary for a website offering guitar tutorial videos.'
    }
  ],
  documentation: [
    "https://ogp.me/#metadata",
    "https://developers.facebook.com/docs/sharing/webmasters/"
  ]
};

const ogDeterminer = {
  name: "og:determiner",
  key: "property",
  description: "Specifies the word that should appear before the title of the resource in social media shares. The determiner is used to clarify the type of the resource.",
  tags: "social-share",
  color: "#FF99CC",
  examples: [
    {
      value: "a",
      description: 'Specifies that the resource is a generic object, like "a video" or "an article".'
    },
    {
      value: "an",
      description: 'Specifies that the resource is a generic object, like "an image" or "an infographic".'
    }
  ],
  documentation: [
    "https://ogp.me/",
    "https://developers.facebook.com/docs/sharing/webmasters#tags"
  ]
};

const ogImage = {
  name: "og:image",
  key: "property",
  color: "#6194EB",
  tags: "social-share",
  description: "Specifies the image to be used when a webpage is shared on social media platforms like Facebook and Twitter.",
  tips: [
    {
      title: "Use high-quality images",
      description: "Make sure to use high-resolution images that are relevant to the content of the webpage. This will attract more attention and provide a better user experience when shared on social media."
    },
    {
      title: "Optimize image size",
      description: "Optimize the image size to reduce the load time of the webpage. Use image compression techniques to maintain image quality while keeping the file size small."
    }
  ],
  examples: [
    {
      value: "https://example.com/image.jpg",
      description: 'Specifies the "og:image" meta tag with the URL of the image to be used when the webpage is shared on social media platforms.'
    }
  ],
  documentation: [
    "https://ogp.me/",
    "https://developers.facebook.com/docs/sharing/webmasters/",
    "https://developer.twitter.com/en/docs/twitter-for-websites/cards/guides/getting-started"
  ]
};

const ogImageAlt = {
  name: "og:image:alt",
  key: "property",
  color: "#FFC107",
  tags: "social-share",
  type: "open-graph-protocol",
  description: 'Specifies alternative text for the image specified in the "og:image" property. This text is used by social media platforms when the image cannot be displayed.',
  tips: [
    {
      title: "Be Descriptive and Concise",
      description: "Use descriptive and concise alternative text that accurately represents the content of the image. This text should be helpful and meaningful for visually impaired users."
    },
    {
      title: "Include Relevant Keywords",
      description: "Consider including relevant keywords in the alternative text, but avoid keyword stuffing or using misleading descriptions. The alternative text should accurately describe the image."
    }
  ],
  examples: [
    {
      value: "An illustration of a couple hiking in the mountains",
      description: "Specifies alternative text for an image of a couple hiking in the mountains."
    },
    {
      value: "A close-up of a delicious pizza",
      description: "Sets the alternative text for an image of a mouth-watering pizza."
    }
  ],
  documentation: [
    "https://ogp.me/",
    "https://developers.facebook.com/docs/sharing/webmasters/"
  ]
};

const ogImageHeight = {
  name: "og:image:height",
  key: "property",
  color: "#FFBF00",
  tags: ["social-share"],
  description: "Specifies the height of the image to be displayed when a web page is shared on social media platforms using Open Graph protocol. It allows for better visualization and optimization of shared content.",
  tips: [
    {
      title: "Provide High-Quality Images",
      description: "Ensure that the og:image property value is set to an image with an appropriate height that is clear, visually appealing, and relevant to the shared content. High-resolution images are recommended for optimal display."
    },
    {
      title: "Consider Aspect Ratio",
      description: "Maintain the aspect ratio of the image to avoid distortion when displayed on different social media platforms."
    },
    {
      title: "Use Recommended Minimum Heights",
      description: "Follow the recommended minimum height guidelines provided by each social media platform to ensure your image is displayed correctly and attractively."
    }
  ],
  examples: [
    {
      value: "630",
      description: 'Specifies the "og:image:height" meta tag with a value of 630 pixels, indicating the height of the shared image.'
    },
    {
      value: "1200",
      description: 'Specifies the "og:image:height" meta tag with a value of 1200 pixels, indicating the height of the shared image.'
    }
  ],
  documentation: [
    "https://ogp.me/",
    "https://developers.facebook.com/docs/sharing/webmasters/images"
  ]
};

const ogImageSecureUrl = {
  name: "og:image:secure_url",
  key: "property",
  color: "#FF9966",
  tags: "social-share",
  description: "Specifies the URL of an image associated with a web page when shared on social media platforms that support the Open Graph Protocol.",
  tips: [
    {
      title: "Use HTTPS",
      description: 'Always use HTTPS for the "og:image:secure_url" meta tag to ensure a secure connection when the image is shared on social media platforms.'
    },
    {
      title: "Optimize Image Size",
      description: 'Make sure the image specified in the "og:image:secure_url" meta tag is optimized for web to improve loading speed and user experience.'
    }
  ],
  examples: [
    {
      value: "https://example.com/image.jpg",
      description: 'Specifies the "og:image:secure_url" meta tag with a secure URL for an image to be displayed when the web page is shared on social media platforms.'
    }
  ],
  documentation: [
    "https://ogp.me/",
    "https://developers.facebook.com/docs/sharing/webmasters#images"
  ]
};

const ogImageType = {
  name: "og:image:type",
  key: "property",
  color: "#FF935D",
  tags: "social-share",
  description: "Specifies the type of content represented by an image in the Open Graph protocol. It provides additional information about the format and content of the image.",
  tips: [
    {
      title: "Choose the Correct Image Type",
      description: "Select the appropriate type that best describes the content of the image. This can help social platforms understand and display the image correctly."
    }
  ],
  examples: [
    {
      value: "image/jpeg",
      description: "Indicates that the image is in JPEG format."
    },
    {
      value: "image/png",
      description: "Specifies that the image is in PNG format."
    }
  ],
  documentation: [
    "https://ogp.me/#type_image"
  ]
};

const ogImageUrl = {
  key: "property",
  name: "og:image:url",
  parameters: [
    { value: "URL", description: "The URL of the image to be displayed in social media shares." }
  ],
  type: "open-graph-protocol",
  color: "#FF8888",
  tags: "social-share",
  description: "Specifies the URL of an image to be displayed when the web page is shared on social media platforms using Open Graph Protocol.",
  tips: [
    {
      title: "Use High-Quality Images",
      description: "To maximize the impact of your shared links on social media, use high-quality images that are visually appealing and relevant to the content."
    },
    {
      title: "Optimize Image Size",
      description: "Optimize the size of the image to ensure fast loading times on social media platforms."
    }
  ],
  examples: [
    {
      value: "https://example.com/image.jpg",
      description: 'Specifies the "og:image:url" meta tag with the URL of an image to be displayed in social media shares.'
    }
  ],
  documentation: [
    "https://ogp.me/#structured",
    "https://developers.facebook.com/docs/sharing/webmasters#images"
  ]
};

const ogImageWidth = {
  name: "og:image:width",
  key: "property",
  color: "#FF77B4",
  tags: "social-share",
  type: "open-graph-protocol",
  description: 'Specifies the width of the image referenced in the "og:image" meta tag. It is used by social media platforms and other services to determine the aspect ratio and display size of the shared image.',
  tips: [
    {
      title: "Ensure image consistency",
      description: 'Set the "og:image:width" meta tag to match the actual width of the image to ensure consistent display across different platforms and devices.'
    }
  ],
  examples: [
    {
      value: "1200",
      description: 'Sets the "og:image:width" meta tag to the width of 1200 pixels for the shared image.'
    },
    {
      value: "1920",
      description: 'Specifies the "og:image:width" meta tag with a width of 1920 pixels for the image displayed when the content is shared.'
    }
  ],
  documentation: [
    "https://ogp.me/#array",
    "https://developers.facebook.com/docs/sharing/webmasters/images/"
  ]
};

const ogLocale = {
  name: "og:locale",
  key: "property",
  color: "#FFB300",
  tags: "social-share",
  description: "Specifies the locale of the web page for Open Graph protocol. It helps to determine the appropriate language and cultural settings for the content when sharing on social media platforms.",
  tips: [
    {
      title: "Use ISO 639-1 Language Code",
      description: 'Follow the ISO 639-1 standard language codes to specify the locale. For example, "en_US" for English (United States) or "fr_FR" for French (France).'
    },
    {
      title: "Default Language",
      description: "If the og:locale meta tag is not specified, the default language will depend on the user's regional settings or the assumed language of the web page."
    }
  ],
  examples: [
    {
      value: "en_US",
      description: 'Sets the "og:locale" meta tag to specify English (United States) as the locale for the Open Graph content.'
    },
    {
      value: "fr_FR",
      description: 'Defines the "og:locale" meta tag to specify French (France) as the locale for the Open Graph content.'
    }
  ],
  documentation: [
    "https://ogp.me/#locales",
    "https://developers.facebook.com/docs/sharing/webmasters#markup"
  ]
};

const ogLocaleAlternate = {
  name: "og:locale:alternate",
  key: "property",
  color: "#FF8C00",
  tags: "social-share",
  description: "Specifies alternative locales for an Open Graph object. It indicates the available translations of the Open Graph object.",
  tips: [
    {
      title: "Use Proper Locale Codes",
      description: 'Use the proper locale codes according to the BCP 47 standard. For example, "en_US" for English (United States) or "fr_FR" for French (France).'
    },
    {
      title: "Include All Available Translations",
      description: 'Ensure that you include all available translations of the Open Graph object by specifying multiple "og:locale:alternate" meta tags for each locale.'
    }
  ],
  examples: [
    {
      value: "en_US",
      description: 'Specifies the "og:locale:alternate" meta tag with the "en_US" locale code to indicate English (United States) translation for the Open Graph object.'
    },
    {
      value: "fr_FR",
      description: 'Specifies the "og:locale:alternate" meta tag with the "fr_FR" locale code to indicate French (France) translation for the Open Graph object.'
    }
  ],
  documentation: [
    "https://ogp.me/#array"
  ]
};

const ogSiteName = {
  name: "og:site_name",
  key: "property",
  color: "#FFB30",
  tags: "social-share",
  description: "Specifies the name of the website or web page that the content belongs to. It is used by social media platforms when displaying shared content.",
  tips: [
    {
      title: "Use a Clear and Recognizable Name",
      description: "Choose a site name that accurately represents your website and is easily recognizable by users."
    }
  ],
  examples: [
    {
      value: "Example Website",
      description: 'Specifies the "og:site_name" meta tag with the name "Example Website" for a web page.'
    }
  ],
  documentation: [
    "https://ogp.me/",
    "https://developers.facebook.com/docs/sharing/webmasters/",
    "https://developer.twitter.com/en/docs/twitter-for-websites/cards/overview/abouts-cards"
  ]
};

const ogTitle = {
  name: "og:title",
  key: "property",
  color: "#FFC107",
  tags: "social-share",
  description: "The og:title meta tag is used to define the title of a webpage when it is shared on social media platforms that support the Open Graph Protocol. It is displayed as the title of the shared link in the feed or post.",
  tips: [
    {
      title: "Make it Compelling",
      description: "Craft an engaging and descriptive title that captures the attention of users and entices them to click on the shared link."
    },
    {
      title: "Keep it Concise",
      description: "Although social media platforms may allow longer titles, it is recommended to keep the og:title tag within 60-70 characters for optimal visibility."
    }
  ],
  examples: [
    {
      value: "Example Article Title",
      description: 'Specifies the og:title meta tag with the title "Example Article Title" for a webpage when it is shared on social media.'
    },
    {
      value: "Product Name - Sale Now!",
      description: 'Defines the og:title meta tag with the title "Product Name - Sale Now!" for a webpage when it is shared on social media platforms.'
    }
  ],
  documentation: [
    "https://ogp.me/",
    "https://developers.facebook.com/docs/sharing/webmasters/"
  ]
};

const ogType = {
  name: "og:type",
  key: "property",
  color: "#FF6700",
  tags: "social-share",
  description: "Specifies the type of object or content being shared on social media platforms using Open Graph Protocol meta tags.",
  tips: [
    {
      title: "Choose the right type",
      description: 'Select the appropriate type that accurately represents the content being shared, such as "website", "article", or "video".'
    },
    {
      title: "Use article type for blog posts",
      description: 'If you are sharing a blog post or an article, set the "og:type" meta tag value to "article" to provide more context to social media platforms.'
    }
  ],
  examples: [
    {
      value: "website",
      description: 'Specifies the "og:type" meta tag with the value "website" for a general webpage or website.'
    },
    {
      value: "article",
      description: 'Defines the "og:type" meta tag with the value "article" for a blog post or article.'
    }
  ],
  documentation: [
    "https://ogp.me/#types",
    "https://developers.facebook.com/docs/sharing/webmasters#markup"
  ]
};

const ogUrl = {
  name: "og:url",
  key: "property",
  color: "#FFC107",
  tags: "social-share",
  description: "Specifies the canonical URL for the Open Graph object. It provides a permanent link to the resource being shared and helps ensure that the correct content is displayed when the URL is shared on social media platforms.",
  tips: [
    {
      title: "Use Absolute URLs",
      description: 'Always use absolute URLs for the "og:url" meta tag to ensure accurate sharing and avoid potential issues with redirection.'
    },
    {
      title: "Include UTM Parameters",
      description: 'Consider adding UTM parameters to the "og:url" URL to track traffic sources and better analyze the performance of your shared content.'
    }
  ],
  examples: [
    {
      value: "https://example.com/blog/article",
      description: 'Specifies the "og:url" meta tag with an absolute URL pointing to the blog article to ensure correct sharing on social media platforms.'
    },
    {
      value: "https://example.com/product/123?utm_source=facebook&utm_medium=social",
      description: 'Defines the "og:url" meta tag with an absolute URL including UTM parameters to track traffic from a specific social media platform.'
    }
  ],
  documentation: [
    "https://ogp.me/#url",
    "https://developers.facebook.com/docs/sharing/webmasters#markup"
  ]
};

const ogVideo = {
  name: "og:video",
  key: "property",
  color: "#FFC300",
  tags: "social-share",
  description: "Specifies the URL of a video to be displayed when a web page is shared on social media platforms that support the Open Graph Protocol. The og:video meta tag is used to provide a thumbnail image, video dimensions, and other video-related metadata.",
  tips: [
    {
      title: "Use a High-Quality Thumbnail Image",
      description: "Choose a visually appealing and descriptive thumbnail image that accurately represents the video content."
    },
    {
      title: "Optimize Video Dimensions and Format",
      description: "Ensure that the video dimensions and format (e.g., MP4) are supported by various social media platforms."
    }
  ],
  examples: [
    {
      value: "https://example.com/video.mp4",
      description: "Specifies the URL of the video file to be displayed on social media when the web page is shared."
    }
  ],
  documentation: [
    "https://ogp.me/",
    "https://developers.facebook.com/docs/sharing/webmasters/#video",
    "https://developer.twitter.com/en/docs/twitter-for-websites/cards/guides/getting-started#video"
  ]
};

const ogVideoAlt = {
  name: "og:video:alt",
  key: "property",
  color: "#EF7D0B",
  tags: "social-share",
  description: "Specifies an alternative text for the video displayed in a social media post when the video cannot be played or is not available. This meta tag is used in conjunction with the Open Graph Protocol (OGP) to enhance the visual representation of shared content.",
  tips: [
    {
      title: "Use descriptive alt text",
      description: "Provide a concise and descriptive alt text that accurately represents the video content. This helps visually impaired users understand the context of the video."
    },
    {
      title: "Keep it brief",
      description: "Limit the alt text to a few words or a short phrase to ensure that it is easily readable and does not clutter the social media post."
    }
  ],
  examples: [
    {
      value: "Explainer video for product XYZ",
      description: 'Specifies the "og:video:alt" meta tag with an alternative text describing the video as an explainer video for product XYZ. This alt text will be displayed when the video cannot be played or is not available.'
    },
    {
      value: "Funny cat compilation",
      description: 'Defines the "og:video:alt" meta tag with an alternative text indicating that the video is a compilation of funny cat videos. This alt text helps users understand the content of the video without playing it.'
    }
  ],
  documentation: [
    "https://ogp.me/",
    "https://developers.facebook.com/docs/sharing/webmasters/#video"
  ]
};

const ogVideoHeight = {
  name: "og:video:height",
  key: "property",
  color: "#FF5733",
  type: "open-graph-protocol",
  tags: "social-share",
  description: "Specifies the height of the video in pixels for Open Graph Protocol (OGP) meta tags. It is used to provide social media platforms with information about the video content and its display dimensions.",
  tips: [
    {
      title: "Ensure Accurate Video Dimensions",
      description: "Provide the correct height value to ensure that the video is displayed with the correct aspect ratio on social media platforms."
    },
    {
      title: "Use the Recommended Aspect Ratio",
      description: "To maintain the video quality across different platforms, it is recommended to use standard aspect ratios like 16:9 or 4:3."
    },
    {
      title: "Consider Responsive Design",
      description: "For responsive web pages, dynamically set the height value based on the device or screen size to optimize video presentation."
    }
  ],
  examples: [
    {
      value: "720",
      description: 'Specifies the "og:video:height" meta tag with a height of 720 pixels for an Open Graph Protocol video, ensuring high-quality display on social media platforms.'
    },
    {
      value: "1080",
      description: 'Defines the "og:video:height" meta tag with a height of 1080 pixels for an Open Graph Protocol video, providing a Full HD experience on supported platforms.'
    }
  ],
  documentation: [
    "https://ogp.me/#structured",
    "https://developers.facebook.com/docs/sharing/webmasters#video"
  ]
};

const ogVideoSecureUrl = {
  name: "og:video:secure_url",
  key: "property",
  color: "#FF6F00",
  tags: "social-share",
  type: "open-graph-protocol",
  description: 'Specifies the URL of a secure video to be displayed when sharing a web page on social media platforms using the Open Graph Protocol. This meta tag is used in combination with the "og:video" meta tag.',
  tips: [
    {
      title: "Use HTTPS Protocol",
      description: "Ensure that the video URL provided is served over a secure HTTPS connection. Most modern browsers require secure connections for media playback, and social media platforms often prioritize secure content."
    },
    {
      title: "Optimize Video Size and Format",
      description: "To provide the best user experience and reduce page loading times, compress and optimize the video file using appropriate codecs and formats. Consider using modern video formats like MP4 with H.264 encoding."
    }
  ],
  examples: [
    {
      value: "https://example.com/videos/myvideo.mp4",
      description: "Specifies the secure URL of a video file in MP4 format for sharing on social media platforms."
    },
    {
      value: "https://example.com/videos/myvideo.webm",
      description: "Defines the secure URL of a video file in WebM format for sharing on social media platforms."
    }
  ],
  documentation: [
    "https://ogp.me/#video"
  ]
};

const ogVideoType = {
  name: "og:video:type",
  key: "property",
  color: "#FFB30",
  tags: "social-share",
  description: "Indicates the type of video content when using Open Graph protocol. It helps social media platforms understand the format of the video for proper handling and display.",
  tips: [
    {
      title: "Specify the Correct Video Type",
      description: 'Ensure that you accurately specify the video type using the "og:video:type" meta tag. This helps social media platforms choose the appropriate video player and settings when sharing your content.'
    }
  ],
  examples: [
    {
      value: "video/mp4",
      description: 'Specifies the "og:video:type" meta tag with the value "video/mp4", indicating that the video is in MP4 format.'
    },
    {
      value: "video/webm",
      description: 'Defines the "og:video:type" meta tag with the value "video/webm", indicating that the video is in WebM format.'
    }
  ],
  documentation: [
    "https://ogp.me/"
  ]
};

const ogVideoUrl = {
  name: "og:video:url",
  key: "property",
  color: "#FF6D00",
  tags: "social-share",
  type: "open-graph-protocol",
  description: "Specifies the URL of a video associated with a web page when shared on social media platforms.",
  tips: [
    {
      title: "Use HTTPS",
      description: "Ensure that the URL provided for the video is served over HTTPS for a secure connection."
    },
    {
      title: "Optimize for Different Platforms",
      description: "Different social media platforms have different video requirements and aspect ratios. Make sure to optimize the video URL accordingly for better visibility and user experience across platforms."
    }
  ],
  examples: [
    {
      value: "https://example.com/video.mp4",
      description: 'Specifies the "og:video:url" meta tag with the URL of a video file in MP4 format.'
    },
    {
      value: "https://example.com/video.webm",
      description: 'Defines the "og:video:url" meta tag with the URL of a video file in WebM format.'
    }
  ],
  documentation: [
    "https://ogp.me/#type_video",
    "https://developers.facebook.com/docs/sharing/webmasters/#videos"
  ]
};

const ogVideoWidth = {
  name: "og:video:width",
  key: "property",
  color: "#FFA500",
  tags: "social-share",
  description: "Specifies the width of the video in pixels when the web page is shared on social media platforms that support the Open Graph Protocol.",
  tips: [
    {
      title: "Use a Responsive Video Player",
      description: "To ensure optimal video playback on various devices, use a responsive video player that automatically adjusts the video width based on the screen size."
    },
    {
      title: "Provide the Correct Video Width",
      description: "Make sure to provide the actual width of the video in pixels. Incorrect values may result in distorted video playback on social media platforms."
    }
  ],
  examples: [
    {
      value: "1280",
      description: 'Specifies the "og:video:width" meta tag with a width of 1280 pixels for a shared web page with a video.'
    },
    {
      value: "1920",
      description: 'Defines the "og:video:width" meta tag with a width of 1920 pixels for a shared web page with a video.'
    }
  ],
  documentation: [
    "https://ogp.me/",
    "https://developers.facebook.com/docs/sharing/webmasters#video"
  ]
};

const profileFirstName = {
  name: "profile:first_name",
  key: "property",
  color: "#FFC300",
  tags: ["social-share"],
  description: "Specifies the first name of the person associated with the web page, particularly for social sharing platforms.",
  tips: [
    {
      title: "Consider Privacy",
      description: "Ensure that you have the necessary consent or permission to include personal information such as the first name in the meta tag."
    }
  ],
  examples: [
    {
      value: "John",
      description: 'Specifies the "profile:first_name" meta tag with the first name "John" for a web page.'
    },
    {
      value: "Jane",
      description: 'Defines the "profile:first_name" meta tag with the first name "Jane" for a web page.'
    }
  ],
  documentation: [
    "https://ogp.me/#type_profile",
    "https://developer.twitter.com/en/docs/twitter-for-websites/cards/guides/getting-started"
  ]
};

const profileGender = {
  name: "profile:gender",
  key: "property",
  color: "#FFA500",
  tags: "social-share",
  description: "Specifies the gender of the person associated with a web page, typically used in the context of social media profiles.",
  tips: [
    {
      title: "Use Appropriate Values",
      description: 'Use values that accurately represent the gender of the person associated with the page, such as "male", "female", or "non-binary".'
    },
    {
      title: "Consider Inclusivity",
      description: 'When using the "profile:gender" meta tag, consider providing an option for users to select "prefer not to say" or a similar inclusive option.'
    }
  ],
  examples: [
    {
      value: "male",
      description: 'Specifies the "profile:gender" meta tag with the value "male" to indicate that the person associated with the page identifies as male.'
    },
    {
      value: "female",
      description: 'Specifies the "profile:gender" meta tag with the value "female" to indicate that the person associated with the page identifies as female.'
    },
    {
      value: "non-binary",
      description: 'Specifies the "profile:gender" meta tag with the value "non-binary" to indicate that the person associated with the page identifies as non-binary.'
    }
  ],
  documentation: [
    "https://developers.facebook.com/docs/marketing-apis/overview/meta-tags#profile-gender",
    "https://developer.twitter.com/en/docs/twitter-for-websites/cards/guides/getting-started#profilegender"
  ]
};

const profileLastName = {
  name: "profile:last_name",
  key: "property",
  color: "#FFEB3B",
  tags: "other",
  description: "Specifies the last name of the individual or entity associated with a social profile. It is used to provide additional information about the profile.",
  tips: [
    {
      title: 'Use with "profile:first_name"',
      description: 'To provide a complete name for a social profile, use the "profile:first_name" meta tag in conjunction with the "profile:last_name" meta tag.'
    },
    {
      title: "Include Accurate Information",
      description: 'Ensure that the last name provided in the "profile:last_name" meta tag accurately represents the individual or entity associated with the social profile.'
    }
  ],
  examples: [
    {
      value: "Doe",
      description: 'Specifies the last name "Doe" for the individual or entity associated with a social profile.'
    },
    {
      value: "Smith",
      description: 'Indicates the last name "Smith" for the individual or entity associated with a social profile.'
    }
  ],
  documentation: [
    "https://developers.facebook.com/docs/marketing-apis/profile#properties",
    "https://developer.mozilla.org/en-US/docs/Web/HTML/Element/meta#attr-profile.last_name"
  ]
};

const profileUsername = {
  name: "profile:username",
  key: "name",
  color: "#FF8C00",
  tags: "social-share",
  description: "Specifies the username or handle associated with a social media profile.",
  tips: [
    {
      title: "Include Social Media Profile",
      description: 'Use the "profile:username" meta tag to specify the username or handle associated with a social media profile. This can enhance the social sharing experience and improve link previews on platforms like Facebook and Twitter.'
    },
    {
      title: "Consistent Format",
      description: 'Ensure that the username or handle used in the "profile:username" meta tag matches the exact username or handle associated with the social media profile. Inconsistent formats may result in incorrect link previews.'
    }
  ],
  examples: [
    {
      value: "@myusername",
      description: 'Specifies the "profile:username" meta tag with the username or handle "@myusername" for a social media profile.'
    },
    {
      value: "myusername",
      description: 'Defines the "profile:username" meta tag with the username or handle "myusername" for a social media profile.'
    }
  ],
  documentation: [
    "https://developers.facebook.com/docs/sharing/webmasters/#markup-multiple-users",
    "https://developer.twitter.com/en/docs/twitter-for-websites/cards/guides/getting-started"
  ]
};

const publisher = {
  name: "publisher",
  key: "name",
  color: "#27AE60",
  tags: "seo",
  description: "Specifies the name of the organization or entity that publishes the web page.",
  tips: [
    {
      title: "Use a Recognizable Name",
      description: "Ensure that the publisher name specified in the meta tag is easily recognizable to users and helps establish trust."
    }
  ],
  examples: [
    {
      value: "Your Company",
      description: `Specifies the "publisher" meta tag with the name of your company as the publisher of the web page, providing information about the entity responsible for the content.`
    },
    {
      value: "Example Magazine",
      description: `Defines the "publisher" meta tag with the name of Example Magazine as the publisher of the web page, establishing the source of the content.`
    }
  ],
  documentation: [
    "https://moz.com/learn/seo/meta-tags",
    "https://ogp.me/#type_article"
  ]
};

const rating = {
  name: "rating",
  key: "name",
  description: "Labels a page as containing adult content, to signal that it be filtered by SafeSearch results.",
  examples: [
    {
      value: "adult",
      description: 'Specifies the "rating" meta tag as "adult," indicating that the web page contains adult content and should be filtered accordingly by SafeSearch.'
    }
  ],
  documentation: [
    "https://developers.google.com/search/docs/advanced/guidelines/safesearch"
  ]
};

const referrer = {
  name: "referrer",
  key: "name",
  color: "#FF8C00",
  tags: "browser",
  description: "Specifies the referrer policy for requests made by the browser.",
  tips: [
    {
      title: "Choose an appropriate referrer policy",
      description: "Consider the privacy and security implications when choosing a referrer policy for your website."
    },
    {
      title: "Use strict referrer policies for sensitive information",
      description: 'If your website handles sensitive user information, it is recommended to use strict referrer policies, such as "no-referrer-when-downgrade" or "strict-origin-when-cross-origin".'
    }
  ],
  examples: [
    {
      value: "no-referrer",
      description: "Specifies that no referrer information should be sent in the HTTP header when navigating to other pages."
    },
    {
      value: "no-referrer-when-downgrade",
      description: "Indicates that the referrer should not be sent when navigating to a less secure URL, such as from HTTPS to HTTP."
    },
    {
      value: "strict-origin-when-cross-origin",
      description: "Specifies that the referrer should only be sent for same-origin requests and requests to a different origin, but with strict privacy restrictions."
    }
  ],
  documentation: [
    "https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Referrer-Policy",
    "https://developers.google.com/web/updates/2016/03/referrer-policy"
  ]
};

const refresh = {
  name: "refresh",
  key: "http-equiv",
  color: "#FF879D",
  tags: ["other", "browser"],
  description: "Used to specify an automatic refresh or redirect of a web page after a specified time interval.",
  tips: [
    {
      title: "Limited Usage",
      description: 'The "refresh" meta tag is not recommended for frequent use as it disrupts the user experience and can negatively impact SEO.'
    },
    {
      title: "Set an Appropriate Time Interval",
      description: 'Ensure that the time interval specified in the "refresh" meta tag is appropriate for the content and purpose of the page.'
    }
  ],
  examples: [
    {
      value: "5; url=https://example.com",
      description: 'Redirects the web page to "https://example.com" after a 5-second delay.'
    },
    {
      value: "10",
      description: "Refreshes the web page after a 10-second delay."
    }
  ],
  documentation: [
    "https://developer.mozilla.org/en-US/docs/Web/HTML/Element/meta/http-equiv#attr-refresh"
  ]
};

const robots = {
  name: "robots",
  key: "name",
  color: "#FF5733",
  tags: "seo",
  description: "Used to control the behavior of search engine crawlers on a web page. It allows developers to specify directives that influence indexing, following links, and other interactions.",
  tips: [
    {
      title: "Use Directives Wisely",
      description: `Carefully choose and use directives, such as "noindex" and "nofollow," to guide search engine behavior according to your site's requirements.`
    },
    {
      title: "Prevent Duplicate Content",
      description: `Using "canonical" and "noindex" directives can help prevent duplicate content issues, improving your site's SEO.`
    },
    {
      title: 'Use "noarchive" to Prevent Cached Copies',
      description: 'Including "noarchive" in the "robots" meta tag prevents search engines from displaying cached copies of the page in their search results.'
    }
  ],
  examples: [
    {
      value: "index, follow",
      description: "Allows search engines to index the page and follow links."
    },
    {
      value: "noindex, nofollow",
      description: "Instructs search engines not to index the page and not to follow any links on the page."
    }
  ],
  parameters: [
    { value: "index", description: "Allows search engines to index the page." },
    { value: "noindex", description: "Instructs search engines not to index the page." },
    { value: "follow", description: "Allows search engines to follow links on the page." },
    { value: "nofollow", description: "Instructs search engines not to follow links on the page." },
    { value: "noarchive", description: "Prevents search engines from displaying cached copies of the page." }
  ],
  documentation: [
    "https://developers.google.com/search/docs/crawling-indexing/robots-meta-tag",
    "https://moz.com/learn/seo/robotstxt"
  ]
};

const themeColor = {
  name: "theme-color",
  key: "name",
  color: "#FF78A3",
  tags: "other",
  description: "Specifies the theme color for a web page. The theme color is used by some browsers to customize the address bar, toolbar, and other interface elements to match the page.",
  tips: [],
  examples: [
    {
      value: "#FF0000",
      description: 'Sets the "theme-color" meta tag to the color red (#FF0000), resulting in a red-themed interface in supporting browsers.'
    },
    {
      value: "#00FF00",
      description: 'Defines the "theme-color" meta tag with the color green (#00FF00), resulting in a green-themed interface in supporting browsers.'
    }
  ],
  documentation: [
    "https://developers.google.com/web/updates/2014/11/Support-for-theme-color-in-Chrome-39-for-Android",
    "https://developer.mozilla.org/en-US/docs/Web/HTML/Element/meta/name/theme-color"
  ]
};

const twitterAppIdIpad = {
  name: "twitter:app:id:ipad",
  key: "name",
  color: "#FFB30D",
  tags: "social-share",
  description: "Specifies the unique identifier for the iPad-specific app associated with the web page, allowing the app to be deep-linked when shared on Twitter.",
  tips: [
    {
      title: "App Deep Linking",
      description: "Ensure that the specified Twitter app ID for iPad is associated with an iOS app that supports deep linking to provide a seamless experience for users."
    }
  ],
  examples: [
    {
      value: "1234567890",
      description: 'Specifies the "twitter:app:id:ipad" meta tag with the unique identifier "1234567890" for the iPad-specific app.'
    }
  ],
  documentation: [
    "https://developer.twitter.com/en/docs/twitter-for-websites/cards/guides/getting-started"
  ]
};

const twitterAppIdIphone = {
  name: "twitter:app:id:iphone",
  key: "name",
  color: "#00ACED",
  tags: "social-share",
  description: "Specifies the Twitter App ID for iOS devices. This meta tag is used to associate your iOS app with your website, allowing users to easily navigate between your website and app.",
  tips: [
    {
      title: "Obtain a Twitter App ID",
      description: "Before using this meta tag, you need to register your iOS app with Twitter and obtain a unique App ID."
    },
    {
      title: "Include the Meta Tag on your Web Page",
      description: 'Place the "twitter:app:id:iphone" meta tag in the head section of your web page, with the "content" attribute set to your Twitter App ID.'
    },
    {
      title: "Test the Association",
      description: "After adding the meta tag, test the association between your website and iOS app using the Twitter Card Validator."
    }
  ],
  examples: [
    {
      value: "123456789",
      description: 'Associates the Twitter App ID "123456789" with the website for iOS devices.'
    }
  ],
  documentation: [
    "https://developer.twitter.com/en/docs/twitter-for-websites/ios-apps/guides/preparing-your-ios-app-to-link-to-your-website"
  ]
};

const twitterAppIdGoogleplay = {
  name: "twitter:app:id:googleplay",
  key: "name",
  color: "#B4C1D7",
  tags: "social-share",
  description: "Specifies the Google Play app ID associated with the website for use on Twitter.",
  tips: [
    {
      title: "Use the Correct App ID",
      description: "Ensure that the specified Google Play app ID is accurate and corresponds to the correct application on the Google Play Store."
    }
  ],
  examples: [
    {
      value: "com.example.app",
      description: 'Specifies the "twitter:app:id:googleplay" meta tag with the Google Play app ID "com.example.app". This allows Twitter to associate the website with the specified app on the Google Play Store.'
    }
  ],
  documentation: [
    "https://developer.twitter.com/en/docs/twitter-for-websites/cards/guides/app-card"
  ]
};

const twitterAppNameGoogleplay = {
  name: "twitter:app:name:googleplay",
  key: "name",
  color: "#913ad6",
  tags: "social-share",
  type: "twitter",
  description: "Specifies the name of the Android app to associate with a webpage when shared on Twitter via Google Play.",
  tips: [
    {
      title: "Choose a Descriptive Name",
      description: "Select a clear and concise app name that accurately represents your Android app."
    },
    {
      title: "Consistency with App Store",
      description: 'Ensure that the name defined with the "twitter:app:name:googleplay" meta tag matches the title of your Android app on the Google Play Store.'
    }
  ],
  examples: [
    {
      value: "My Awesome App",
      description: 'Specifies the name "My Awesome App" for the associated Android app when shared on Twitter via Google Play.'
    }
  ],
  documentation: [
    "https://developer.twitter.com/en/docs/twitter-for-websites/cards/guides/app-card"
  ]
};

const twitterAppNameIphone = {
  name: "twitter:app:name:iphone",
  key: "name",
  color: "#1DA1F2",
  tags: "social-share",
  description: "Specifies the name of your iPhone app if you have one associated with your website. This meta tag is used for Twitter sharing on iOS devices and allows users to open your app directly from a tweet.",
  tips: [
    {
      title: "Provide a Consistent App Experience",
      description: 'Make sure the name specified in the "twitter:app:name:iphone" meta tag matches the actual name of your iPhone app in the App Store. This will provide a seamless user experience when opening your app from a tweet.'
    },
    {
      title: "Include Deep Linking",
      description: "To enhance user engagement, consider implementing deep linking within your iPhone app. This will allow users to be directed to specific content within the app when they open it from a tweet."
    }
  ],
  examples: [
    {
      value: "MyApp",
      description: 'Specifies the name of a fictional iPhone app called "MyApp" for Twitter sharing on iOS devices.'
    }
  ],
  documentation: [
    "https://developer.twitter.com/en/docs/twitter-for-websites/cards/overview/markup",
    "https://developer.twitter.com/en/docs/twitter-for-websites/cards/guides/getting-started"
  ]
};

const twitterAppNameIpad = {
  name: "twitter:app:name:ipad",
  key: "name",
  color: "#FF3366",
  tags: "social-share",
  description: "Specifies the name of the iPad-optimized app that should be used to open the webpage when shared on Twitter.",
  tips: [
    {
      title: "Use the official app name",
      description: "Provide the accurate name of the iPad-optimized app to ensure a consistent experience for users when they open the shared webpage."
    }
  ],
  examples: [
    {
      value: "MyApp",
      description: 'Specifies the "twitter:app:name:ipad" meta tag with the value "MyApp", indicating that the webpage should be opened in the "MyApp" iPad-optimized app when shared on Twitter.'
    },
    {
      value: "AnotherApp",
      description: 'Defines the "twitter:app:name:ipad" meta tag with the value "AnotherApp", specifying that the shared webpage should be opened in the "AnotherApp" app optimized for iPad.'
    }
  ],
  documentation: [
    "https://developer.twitter.com/en/docs/twitter-for-websites/cards/overview/app-ipad-name"
  ]
};

const twitterAppUrlGoogleplay = {
  name: "twitter:app:url:googleplay",
  key: "name",
  color: "#29B6F6",
  tags: "social-share",
  description: "Specifies the custom URL scheme for an Android app on the Google Play Store. It allows users to open the app directly from a link in a Twitter post on Android devices.",
  tips: [
    {
      title: "Use Deep Linking",
      description: 'Make sure the custom URL scheme specified in the "twitter:app:url:googleplay" meta tag is supported and properly configured in your Android app.'
    },
    {
      title: "Provide a Relevant Page",
      description: "Ensure that the custom URL scheme specified in the meta tag points to a relevant page within your Android app, improving the user experience."
    }
  ],
  examples: [
    {
      value: "myapp://playstore?id=com.example.myapp",
      description: 'Specifies the "twitter:app:url:googleplay" meta tag with a custom URL scheme for the Android app on the Google Play Store. The scheme opens the app directly to the page with the ID "com.example.myapp."'
    }
  ],
  documentation: [
    "https://developer.twitter.com/en/docs/twitter-for-websites/cards/overview/markup"
  ]
};

const twitterAppUrlIpad = {
  name: "twitter:app:url:ipad",
  key: "name",
  description: "The URL to open your app to a specific page in the Twitter app on iPad.",
  tags: ["social-share"],
  color: "#FFCDD2",
  examples: [
    {
      value: "twitter://page?id=12345",
      description: "Opens the Twitter app on iPad and navigates to the page with the specified ID."
    }
  ],
  documentation: [
    "https://developer.twitter.com/en/docs/twitter-for-websites/timelines/guides/parameter-reference-ios"
  ]
};

const twitterAppUrlIphone = {
  name: "twitter:app:url:iphone",
  key: "name",
  color: "#0390fc",
  tags: "social-share",
  description: "Specifies the deep link URL for the iOS app associated with the website when shared on Twitter using an iPhone.",
  tips: [
    {
      title: "Use a Deep Link URL",
      description: "Provide a deep link URL that opens a specific section or page within your iOS app when shared on Twitter using an iPhone."
    },
    {
      title: "Ensure App Integration",
      description: "Make sure your iOS app is integrated with the Twitter app by implementing the necessary app-specific URL schemes."
    }
  ],
  examples: [
    {
      value: "yourapp://deeplink",
      description: 'Specifies the "twitter:app:url:iphone" meta tag with the deep link URL for the iOS app "yourapp" when shared on Twitter using an iPhone.'
    }
  ],
  documentation: [
    "https://developer.twitter.com/en/docs/twitter-for-websites/cards/guides/getting-started"
  ]
};

const twitterCard = {
  name: "twitter:card",
  key: "name",
  color: "#1DA1F2",
  tags: "social-share",
  description: "Specifies the card type to be used when a link to a web page is shared on Twitter. The card type determines how the shared content appears on Twitter.",
  tips: [
    {
      title: "Choose the Appropriate Card Type",
      description: 'Select the most suitable card type based on the content you want to display on Twitter. The available card types include "summary", "summary_large_image", "app", "player", and "gallery". Refer to the Twitter documentation for guidelines on using each card type.'
    },
    {
      title: "Add Relevant Meta Tags",
      description: 'Include other relevant meta tags such as "twitter:title", "twitter:description", and "twitter:image" to provide additional information and optimize the appearance of the shared content on Twitter.'
    }
  ],
  examples: [
    {
      value: "summary",
      description: 'Specifies the "twitter:card" meta tag with the "summary" card type, which displays a small thumbnail, a title, and a description of the shared content on Twitter.'
    },
    {
      value: "summary_large_image",
      description: 'Defines the "twitter:card" meta tag with the "summary_large_image" card type, which displays a large image in addition to the title and description of the shared content on Twitter.'
    }
  ],
  documentation: [
    "https://developer.twitter.com/en/docs/twitter-for-websites/cards/overview/abouts-cards"
  ]
};

const twitterCreator = {
  name: "twitter:creator",
  key: "name",
  color: "#00acee",
  tags: "social-share",
  description: "Indicates the Twitter username of the content creator or author for a webpage.",
  tips: [
    {
      title: "Use an @username",
      description: 'Make sure to include the "@" symbol before the Twitter username in the value of the "twitter:creator" meta tag.'
    },
    {
      title: "Use a Real Twitter Account",
      description: "Provide the Twitter username of the actual content creator or author on Twitter. This allows users to easily find and connect with the creator on Twitter."
    }
  ],
  examples: [
    {
      value: "@username",
      description: 'Specifies the "twitter:creator" meta tag with the Twitter username of the content creator or author for a webpage.'
    }
  ],
  documentation: [
    "https://developer.twitter.com/en/docs/twitter-for-websites/cards/guides/getting-started",
    "https://developer.twitter.com/en/docs/twitter-for-websites/cards/overview/markup"
  ]
};

const twitterCreatorId = {
  name: "twitter:creator:id",
  key: "name",
  color: "#85c1e9",
  tags: "social-share",
  description: "Specifies the Twitter user ID of the content creator or author. This meta tag helps Twitter display the correct Twitter card when the content is shared on the platform.",
  tips: [
    {
      title: "Use numeric user ID",
      description: "Make sure to use the numeric ID of the Twitter user instead of their username. This ensures accurate identification of the content creator."
    }
  ],
  examples: [
    {
      value: "@JohnDoe",
      description: 'Incorrect usage: Specifies the Twitter username "@JohnDoe" as the content creator ID. This may lead to incorrect display of the Twitter card.'
    },
    {
      value: "1234567890",
      description: 'Correct usage: Specifies the numeric user ID "1234567890" as the content creator ID. This ensures accurate identification of the content creator.'
    }
  ],
  documentation: [
    "https://developer.twitter.com/en/docs/twitter-for-websites/cards/overview/markup",
    "https://developer.twitter.com/en/docs/twitter-for-websites/cards/guides/getting-started"
  ]
};

const twitterData1 = {
  name: "twitter:data1",
  key: "name",
  color: "#00ACEE",
  tags: "social-share",
  description: 'A data field used by Twitter Cards to display additional information in a tweet containing a URL to a web page. The "twitter:data1" meta tag allows you to specify the value for the data field, which can be used to provide context or important details about the shared content.',
  tips: [
    {
      title: "Choose relevant and compelling data",
      description: 'Select a value for "twitter:data1" that is relevant to the content being shared and will catch the attention of users.'
    },
    {
      title: "Use appropriate data format",
      description: 'Ensure that the value for "twitter:data1" is formatted correctly according to the expected data type, such as numbers, dates, or custom data formats.'
    }
  ],
  examples: [
    {
      value: "5.99",
      description: 'Specifies the "twitter:data1" meta tag with the value of "5.99" to display a price or monetary value in a tweet.'
    },
    {
      value: "January 1, 2022",
      description: 'Defines the "twitter:data1" meta tag with the value of "January 1, 2022" to display a specific date in a tweet.'
    }
  ],
  documentation: [
    "https://developer.twitter.com/en/docs/twitter-for-websites/cards/guides/getting-started"
  ]
};

const twitterData2 = {
  name: "twitter:data2",
  key: "name",
  color: "#FF00FF",
  tags: "social-share",
  description: 'A custom meta tag for specifying a secondary value associated with the shared content on Twitter. This meta tag is used in conjunction with the "twitter:card" meta tag to provide additional information or context about the shared content.',
  tips: [
    {
      title: "Use Unique and Relevant Data",
      description: 'Ensure that the value provided for the "data2" meta tag is unique and relevant to the shared content. This can help improve the visibility and understanding of the shared content on Twitter.'
    },
    {
      title: "Consider Length Limitations",
      description: 'Be aware that Twitter has character limitations for the data values in meta tags. Consider the length of the "data2" value to ensure it fits within the allowed limit.'
    },
    {
      title: "Use Appropriate Data Type",
      description: 'Choose an appropriate data type for the "data2" value based on the content being shared. It can be a string, number, or any other valid data type supported by Twitter.'
    }
  ],
  examples: [
    {
      value: "Author Name",
      description: 'Specifies the "data2" meta tag with the name of the author associated with the shared content. This provides additional context about the content on Twitter.'
    },
    {
      value: "Publication Date",
      description: 'Defines the "data2" meta tag with the publication date of the shared content. This adds relevant information for users on Twitter.'
    }
  ],
  documentation: [
    "https://developer.twitter.com/en/docs/twitter-for-websites/cards/overview/markup"
  ]
};

const twitterDescription = {
  name: "twitter:description",
  key: "property",
  type: "twitter",
  color: "#1DA1F2",
  tags: "social-share",
  description: "Provides a concise description of the content being shared on Twitter. This meta tag is used by Twitter when a webpage URL is shared on the platform.",
  tips: [
    {
      title: "Use Concise and Compelling Descriptions",
      description: "Make sure your Twitter description accurately represents the content and entices users to click through to your webpage."
    },
    {
      title: "Optimize for Twitter Card Display",
      description: "To enhance the appearance of shared links on Twitter, consider implementing Twitter Cards, which provide a rich media preview of your webpage."
    }
  ],
  examples: [
    {
      value: "Check out this amazing article on web development!",
      description: 'Specifies the "twitter:description" meta tag with a brief description of the webpage content being shared on Twitter.'
    },
    {
      value: "Discover the latest trends in design and development.",
      description: 'Sets the "twitter:description" meta tag with a concise description of the webpage content to be displayed on Twitter.'
    }
  ],
  documentation: [
    "https://developer.twitter.com/en/docs/twitter-for-websites/cards/guides/getting-started"
  ]
};

const twitterImage = {
  name: "twitter:image",
  key: "property",
  color: "#1DA1F2",
  tags: "social-share",
  description: "Specifies the URL of the image to be displayed in tweets when a web page is shared on Twitter. The image should have a minimum size of 120x120px and a maximum size of 4096x4096px.",
  tips: [
    {
      title: "Use High-Resolution Images",
      description: "To ensure optimal image quality, use high-resolution images with an aspect ratio of 1:1 and a minimum size of 120x120px."
    },
    {
      title: "Consider Image Placement",
      description: "Keep in mind that the shared image may be cropped on certain devices and platforms, so make sure the important elements are centered."
    }
  ],
  examples: [
    {
      value: "https://example.com/img/twitter.jpg",
      description: 'Specifies the "twitter:image" meta tag with the URL of a JPEG image to be displayed in tweets when a web page is shared on Twitter.'
    }
  ],
  documentation: [
    "https://developer.twitter.com/en/docs/twitter-for-websites/cards/overview/summary-card-with-large-image"
  ]
};

const twitterImageAlt = {
  name: "twitter:image:alt",
  key: "name",
  color: "#FFDD85",
  tags: "social-share",
  description: "Specifies the alternative text for an image when shared on Twitter. Alternative text provides a text description of the image for users who can't see it, such as those using screen readers or with slow internet connections.",
  tips: [
    {
      title: "Be Descriptive",
      description: "Ensure that the alternative text accurately describes the content and purpose of the image. Use relevant keywords but avoid keyword stuffing."
    },
    {
      title: "Keep it Concise",
      description: "Alternative text should be concise and to the point, while still providing enough context for users to understand the image."
    },
    {
      title: "Avoid Repetition",
      description: "If an image is used multiple times within a page or across multiple pages, ensure that the alternative text remains unique and descriptive for each instance."
    },
    {
      title: "Use Plain Language",
      description: "Avoid using jargon or technical language in the alternative text. Use plain and simple language that is easily understandable."
    }
  ],
  examples: [
    {
      value: "A person holding a smartphone",
      description: 'Specifies the "twitter:image:alt" meta tag with alternative text describing a person holding a smartphone, which helps visually impaired users understand the image content.'
    },
    {
      value: "A red bicycle on a sunny day",
      description: `Defines the "twitter:image:alt" meta tag with alternative text describing a red bicycle on a sunny day, providing context for users who can't see the image.`
    }
  ],
  documentation: [
    "https://developer.twitter.com/en/docs/twitter-for-websites/cards/guides/getting-started"
  ]
};

const twitterImageHeight = {
  name: "twitter:image:height",
  key: "name",
  color: "#FFAC33",
  tags: "social-share",
  description: "Specifies the height of the image to be displayed when a web page is shared on Twitter. It is used by Twitter to properly display the image in the tweet.",
  tips: [
    {
      title: "Use Optimal Image Height",
      description: "Ensure that the height of the image matches the recommended dimensions provided by Twitter for optimal display."
    },
    {
      title: "Consider Aspect Ratio",
      description: "Maintaining the aspect ratio of the image is important to avoid distortion or cropping when displayed on Twitter."
    }
  ],
  examples: [
    {
      value: "1200",
      description: 'Sets the "twitter:image:height" meta tag to 1200 pixels, indicating the height of the image to be displayed on Twitter when the web page is shared.'
    }
  ],
  documentation: [
    "https://developer.twitter.com/en/docs/twitter-for-websites/cards/guides/getting-started"
  ]
};

const twitterImageType = {
  name: "twitter:image:type",
  key: "name",
  description: 'Specifies the type of the image referenced in the "twitter:image" meta tag. This meta tag is used to define the type of image file that is being shared on Twitter.',
  tags: "social-share",
  color: "#FFB536",
  tips: [
    {
      title: "Choose the Appropriate Image Type",
      description: 'Select the correct image type for the "twitter:image:type" meta tag based on the format of the image file being shared. This ensures that the image is displayed correctly on Twitter.'
    }
  ],
  examples: [
    {
      value: "image/jpeg",
      description: 'An example that specifies the "twitter:image:type" meta tag with the value "image/jpeg", indicating that the image being shared is in JPEG format.'
    },
    {
      value: "image/png",
      description: 'An example that defines the "twitter:image:type" meta tag with the value "image/png", indicating that the image being shared is in PNG format.'
    }
  ],
  documentation: [
    "https://developer.twitter.com/en/docs/twitter-for-websites/cards/guides/getting-started#image",
    "https://developer.twitter.com/en/docs/twitter-for-websites/cards/guides/summary-card-with-large-image"
  ]
};

const twitterImageWidth = {
  name: "twitter:image:width",
  key: "name",
  color: "#FF8C42",
  tags: "social-share",
  description: "Specifies the width of the image to be displayed when sharing a web page on Twitter.",
  tips: [
    {
      title: "Optimize Image Size",
      description: "Ensure that the image being shared has the specified width to enhance the visual appearance on Twitter."
    }
  ],
  examples: [
    {
      value: "1200",
      description: 'Sets the "twitter:image:width" meta tag value to 1200 pixels, indicating the width of the image to be displayed in tweets.'
    },
    {
      value: "800",
      description: 'Specifies the width of the image to be 800 pixels when shared on Twitter using the "twitter:image:width" meta tag.'
    }
  ],
  documentation: [
    "https://developer.twitter.com/en/docs/twitter-for-websites/cards/guides/getting-started",
    "https://dev.twitter.com/cards/types/summary-large-image"
  ]
};

const twitterLabel1 = {
  name: "twitter:label1",
  key: "name",
  type: "twitter",
  color: "#1DA1F2",
  tags: "social-share",
  description: "Used to define the label for the first data field in a Twitter card. Twitter cards allow you to attach rich media experiences to tweets shared from your website.",
  tips: [
    {
      title: "Use Clear and Concise Labels",
      description: "Choose a label that accurately describes the data field and provides useful information to users."
    },
    {
      title: "Keep it Short",
      description: "Keep the label brief to ensure it fits within the limited space available in a tweet."
    }
  ],
  examples: [
    {
      value: "Author",
      description: 'Specifies the "twitter:label1" meta tag with the label "Author" for the first data field in a Twitter card.'
    },
    {
      value: "Location",
      description: 'Defines the "twitter:label1" meta tag with the label "Location" for the first data field in a Twitter card.'
    }
  ],
  documentation: [
    "https://developer.twitter.com/en/docs/twitter-for-websites/cards/overview/markup"
  ]
};

const twitterLabel2 = {
  name: "twitter:label2",
  key: "property",
  description: "Custom label for the second value of a Twitter card.",
  tags: "social-share",
  color: "#FFA500",
  examples: [
    {
      value: "Year",
      description: "Specifies a custom label for the year value in a Twitter card."
    },
    {
      value: "Category",
      description: "Defines a custom label for the category value in a Twitter card."
    }
  ],
  documentation: [
    "https://developer.twitter.com/en/docs/twitter-for-websites/cards/guides/getting-started"
  ]
};

const twitterPlayer = {
  name: "twitter:player",
  key: "name",
  color: "#1DA1F2",
  tags: "social-share",
  description: 'Specifies the URL to a Twitter card player that should be used when the URL in the "twitter:card" meta tag is set to "player".',
  tips: [
    {
      title: "Provide a Secure URL",
      description: "Make sure the URL provided for the Twitter card player is using HTTPS to ensure secure communication."
    },
    {
      title: "Optimize for Mobile",
      description: "Ensure that the Twitter card player works well on mobile devices, as a significant portion of Twitter users access the platform from their smartphones."
    }
  ],
  examples: [
    {
      value: "https://example.com/video.mp4",
      description: "Specifies the URL to a video file that should be played when the associated Twitter card is displayed in a tweet."
    }
  ],
  documentation: [
    "https://developer.twitter.com/en/docs/twitter-for-websites/cards/guides/getting-started"
  ]
};

const twitterPlayerHeight = {
  key: "name",
  name: "twitter:player:height",
  color: "#FF318E",
  tags: "social-share",
  type: "twitter",
  description: "Specifies the height of the Twitter player card when embedded in a tweet. The player card allows you to attach rich media experiences, such as videos or interactive content, to your tweets.",
  tips: [
    {
      title: "Provide an appropriate height",
      description: "Ensure that you set the height of the Twitter player card to match the aspect ratio of your media to avoid distorted or cropped content."
    },
    {
      title: "Consider mobile devices",
      description: "Due to limited screen space on mobile devices, it is recommended to use a responsive height value for the Twitter player card to ensure optimal display across different devices and orientations."
    }
  ],
  examples: [
    {
      value: "450",
      description: 'Sets the "twitter:player:height" meta tag to 450 pixels, indicating the height of the embedded Twitter player card as 450 pixels.'
    },
    {
      value: "100%",
      description: 'Specifies the "twitter:player:height" meta tag as a percentage value, allowing the Twitter player card to adapt to the available space dynamically.'
    }
  ],
  documentation: [
    "https://developer.twitter.com/en/docs/twitter-for-websites/cards/overview/player-card"
  ]
};

const twitterPlayerStream = {
  name: "twitter:player:stream",
  key: "name",
  color: "#00ACEE",
  tags: "social-share",
  description: "Specifies the URL to a live video stream on Twitter. When shared on Twitter, this meta tag allows the video player to display and play the live stream directly in the tweet.",
  tips: [
    {
      title: "Use a Live Video Stream URL",
      description: 'Ensure that the value for the "twitter:player:stream" meta tag is a valid URL pointing to a live video stream. The video player on Twitter will use this URL to display the stream directly in tweets.'
    },
    {
      title: "Check Video Stream Compatibility",
      description: "Make sure that the live video stream URL is compatible with Twitter's video player requirements and formats. Check the documentation provided by Twitter for more details on supported formats."
    }
  ],
  examples: [
    {
      value: "https://example.com/live-stream",
      description: 'Specifies the "twitter:player:stream" meta tag with the URL to a live video stream. When shared on Twitter, the tweet will display the live stream directly within the Twitter video player.'
    }
  ],
  documentation: [
    "https://developer.twitter.com/en/docs/twitter-for-websites/cards/overview/player-card"
  ]
};

const twitterPlayerWidth = {
  name: "twitter:player:width",
  key: "name",
  color: "#FFB30D",
  tags: "social-share",
  description: "Specifies the width of the Twitter card player on a web page when shared on Twitter. The Twitter card player allows users to play video or audio content directly within a tweet.",
  tips: [
    {
      title: "Set an Appropriate Width",
      description: "Choose a width that provides a good user experience and fits well within a tweet. Avoid setting an excessively wide or narrow width that may cause usability issues."
    },
    {
      title: "Consider Responsive Design",
      description: "Make sure that the player width is responsive and adapts well to different screen sizes and devices to ensure a consistent user experience."
    }
  ],
  examples: [
    {
      value: "480",
      description: 'Sets the "twitter:player:width" meta tag with a width of 480 pixels, providing a moderate-sized player for Twitter card content.'
    },
    {
      value: "640",
      description: 'Specifies the "twitter:player:width" meta tag with a width of 640 pixels, providing a larger player size for better visibility on Twitter cards.'
    }
  ],
  documentation: [
    "https://developer.twitter.com/en/docs/twitter-for-websites/cards/guides/getting-started"
  ]
};

const twitterSite = {
  key: "name",
  name: "twitter:site",
  color: "#1DA1F2",
  tags: "social-share",
  type: "twitter",
  description: "Specifies the Twitter username of the website or author associated with a webpage.",
  tips: [
    {
      title: "Use Your Twitter Username",
      description: 'Provide your Twitter username in the "content" attribute to associate your website or content with your Twitter account.'
    },
    {
      title: "Use @mention Instead of Full URL",
      description: "Instead of using the full URL, use the Twitter handle (@mention) to provide a more concise and easily recognizable association."
    },
    {
      title: "Use Consistent Twitter Username",
      description: 'Ensure that the Twitter username used in the "twitter:site" meta tag matches the actual Twitter handle of the website or author.'
    }
  ],
  examples: [
    {
      value: "@exampleUsername",
      description: 'Specifies the Twitter username for a website or author as "@exampleUsername".'
    },
    {
      value: "@moz",
      description: 'Associates the webpage with the Twitter account of Moz (a popular SEO software company) by specifying the Twitter handle as "@moz".'
    }
  ],
  documentation: [
    "https://developer.twitter.com/en/docs/twitter-for-websites/cards/overview/markup",
    "https://moz.com/learn/seo/meta-tag"
  ]
};

const twitterSiteId = {
  name: "twitter:site:id",
  key: "name",
  color: "#1DA1F2",
  tags: "social-share",
  description: "Specifies the Twitter username associated with the website or content.",
  tips: [
    {
      title: "Use the Twitter Username",
      description: "Provide your Twitter site username to associate your website or content with your Twitter account."
    },
    {
      title: "Ensure Consistency",
      description: "Use the same Twitter username across all platforms and channels to maintain brand consistency and make it easier for users to find and follow you."
    }
  ],
  examples: [
    {
      value: "@example",
      description: 'Assigns the Twitter username "@example" to the website or content.'
    }
  ],
  documentation: [
    "https://developer.twitter.com/en/docs/twitter-for-websites/cards/guides/getting-started"
  ]
};

const twitterTitle = {
  name: "twitter:title",
  key: "name",
  color: "#33CCFF",
  tags: "social-share",
  description: "Specifies the title of a webpage when shared on Twitter. It is used to provide a concise and compelling title that grabs users' attention and encourages engagement.",
  tips: [
    {
      title: "Keep it Short",
      description: "Twitter has a character limit for tweet content, so ensure that the title is concise and compelling within that limit."
    },
    {
      title: "Include Keywords",
      description: "Including relevant keywords in the title can help improve visibility and search engine optimization on Twitter."
    },
    {
      title: "Use Dynamic Titles",
      description: "For better engagement, consider using dynamic titles that change according to the content being shared, rather than static titles."
    }
  ],
  examples: [
    {
      value: "My Webpage Title",
      description: 'Specifies the "twitter:title" meta tag with a static title for a webpage shared on Twitter.'
    },
    {
      value: "{pageTitle} - {siteName}",
      description: 'Defines the "twitter:title" meta tag with a dynamic title for a webpage shared on Twitter, including the page title and site name variables.'
    }
  ],
  documentation: [
    "https://developer.twitter.com/en/docs/twitter-for-websites/cards/guides/getting-started"
  ]
};

const viewport = {
  name: "viewport",
  key: "name",
  color: "#FFB369",
  tags: "browser",
  description: "Specifies the viewport characteristics for a web page, including dimensions, scaling, and zooming options.",
  tips: [
    {
      title: "Set the initial-scale",
      description: 'Use the "initial-scale" property to control the initial zoom level when the page is loaded. A value of 1.0 indicates no zoom.'
    },
    {
      title: "Specify width and height",
      description: 'Include the "width" and "height" properties to define the dimensions of the viewport. This helps ensure proper rendering on different devices.'
    },
    {
      title: 'Use "user-scalable" carefully',
      description: 'Be cautious when setting the "user-scalable" property. Disabling user scalability can lead to accessibility issues and a poor user experience. Consider allowing users to zoom in or out if necessary.'
    }
  ],
  examples: [
    {
      value: "width=device-width, initial-scale=1.0",
      description: 'Defines the "viewport" meta tag with the width and initial-scale properties set to the device width and 1.0, respectively. This ensures that the page is displayed at 100% zoom initially.'
    },
    {
      value: "width=800, height=600",
      description: 'Specifies the "viewport" meta tag with the width and height properties set to fixed values of 800 and 600 pixels, respectively. This is useful for non-responsive pages where a specific viewport size is required.'
    },
    {
      value: "width=device-width, initial-scale=1.0, user-scalable=no",
      description: 'Sets the "viewport" meta tag with the width, initial-scale, and user-scalable properties defined. Disabling user scalability can be beneficial for certain scenarios where maintaining a consistent zoom level is critical.'
    }
  ],
  documentation: [
    "https://developer.mozilla.org/en-US/docs/Meta/Viewport_tag",
    "https://developers.google.com/web/fundamentals/design-and-ux/responsive"
  ]
};

const xUaCompatible = {
  name: "x-ua-compatible",
  key: "http-equiv",
  color: "#FF8000",
  tags: "browser",
  description: "Used to specify the document compatibility mode for Internet Explorer (IE). It allows developers to ensure that their webpage is rendered using the appropriate version of IE, avoiding compatibility issues.",
  tips: [
    {
      title: "Specify Compatible Document Mode",
      description: 'Set the "x-ua-compatible" meta tag to specify the document compatibility mode your webpage should be rendered in IE.'
    }
  ],
  examples: [
    {
      value: "IE=edge",
      description: 'Specifies the "x-ua-compatible" meta tag with "IE=edge" to force IE to use the highest document mode available.'
    },
    {
      value: "IE=9",
      description: 'Defines the "x-ua-compatible" meta tag with "IE=9" to ensure IE renders the webpage using Internet Explorer 9 document mode.'
    }
  ],
  documentation: [
    "https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/X-UA-Compatible",
    "https://docs.microsoft.com/en-us/openspecs/ie_standards/ms-decst/6ec87709-cf13-4a88-ac1c-3fe2c607b5f8"
  ]
};

const metaFlatSchema = {
  appleItunesApp,
  appleMobileWebAppCapable,
  appleMobileWebAppStatusBarStyle,
  appleMobileWebAppTitle,
  applicationName,
  articleAuthor,
  articleExpirationTime,
  articleModifiedTime,
  articlePublishedTime,
  articleSection,
  articleTag,
  author,
  bookAuthor,
  bookIsbn,
  bookReleaseDate,
  bookTag,
  charset,
  colorScheme,
  contentSecurityPolicy,
  contentType,
  creator,
  defaultStyle,
  description,
  fbAppId,
  formatDetection,
  generator,
  google,
  googleSiteVerification,
  googlebot,
  googlebotNews,
  keywords,
  mobileWebAppCapable,
  msapplicationConfig,
  msapplicationTileColor,
  msapplicationTileImage,
  ogAudio,
  ogAudioSecureUrl,
  ogAudioType,
  ogAudioUrl,
  ogDescription,
  ogDeterminer,
  ogImage,
  ogImageAlt,
  ogImageHeight,
  ogImageSecureUrl,
  ogImageType,
  ogImageUrl,
  ogImageWidth,
  ogLocale,
  ogLocaleAlternate,
  ogSiteName,
  ogTitle,
  ogType,
  ogUrl,
  ogVideo,
  ogVideoAlt,
  ogVideoHeight,
  ogVideoSecureUrl,
  ogVideoType,
  ogVideoUrl,
  ogVideoWidth,
  profileFirstName,
  profileGender,
  profileLastName,
  profileUsername,
  publisher,
  rating,
  referrer,
  refresh,
  robots,
  themeColor,
  twitterAppIdIpad,
  twitterAppIdIphone,
  twitterAppIdGoogleplay,
  twitterAppNameIpad,
  twitterAppNameGoogleplay,
  twitterAppNameIphone,
  twitterAppUrlGoogleplay,
  twitterAppUrlIpad,
  twitterAppUrlIphone,
  twitterCard,
  twitterCreator,
  twitterCreatorId,
  twitterData1,
  twitterData2,
  twitterDescription,
  twitterImage,
  twitterImageAlt,
  twitterImageHeight,
  twitterImageType,
  twitterImageWidth,
  twitterLabel1,
  twitterLabel2,
  twitterPlayer,
  twitterPlayerHeight,
  twitterPlayerStream,
  twitterPlayerWidth,
  twitterSite,
  twitterSiteId,
  twitterTitle,
  viewport,
  xUaCompatible
};

export { metaFlatSchema };
