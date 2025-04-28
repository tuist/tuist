type Booleanable = boolean | 'false' | 'true' | '';
type Stringable = string | Booleanable | number;
type Arrayable<T> = T | Array<T>;
interface DataKeys {
    [key: `data-${string}`]: Stringable;
}
type DefinedValueOrEmptyObject<T extends undefined | Record<string, any>> = [T] extends [undefined] ? ({}) : T;
type Merge<T extends undefined | Record<string, any>, D = {}> = [T] extends [undefined] ? D : D & T;
interface MergeHead {
    base?: {};
    link?: {};
    meta?: {};
    style?: {};
    script?: {};
    noscript?: {};
    htmlAttrs?: {};
    bodyAttrs?: {};
}
type MaybePromiseProps<T> = T | {
    [key in keyof T]?: T[key] | Promise<T[key]>;
};

type ReferrerPolicy = '' | 'no-referrer' | 'no-referrer-when-downgrade' | 'origin' | 'origin-when-cross-origin' | 'same-origin' | 'strict-origin' | 'strict-origin-when-cross-origin' | 'unsafe-url';

interface MetaFlatArticle {
    /**
     * Writers of the article.
     * @example ['https://example.com/some.html', 'https://example.com/one.html']
     */
    articleAuthor?: string[];
    /**
     * When the article is out of date after.
     * @example '1970-01-01T00:00:00.000Z'
     */
    articleExpirationTime?: string;
    /**
     * When the article was last changed.
     * @example '1970-01-01T00:00:00.000Z'
     */
    articleModifiedTime?: string;
    /**
     * When the article was first published.
     * @example '1970-01-01T00:00:00.000Z'
     */
    articlePublishedTime?: string;
    /**
     * A high-level section name.
     * @example 'Technology'
     */
    articleSection?: string;
    /**
     * Tag words associated with this article.
     * @example ['Apple', 'Steve Jobs]
     */
    articleTag?: string[];
}
interface MetaFlatBook {
    /**
     * Who wrote this book.
     * @example ['https://example.com/some.html', 'https://example.com/one.html']
     */
    bookAuthor?: string[];
    /**
     * The ISBN.
     * @example '978-3-16-148410-0'
     */
    bookIsbn?: string;
    /**
     * The date the book was released.
     * @example '1970-01-01T00:00:00.000Z'
     */
    bookReleaseDate?: string;
    /**
     * Tag words associated with this book.
     * @example ['Apple', 'Steve Jobs]
     */
    bookTag?: string[];
}
interface MetaFlatProfile {
    /**
     * A name normally given to an individual by a parent or self-chosen.
     */
    profileFirstName?: string;
    /**
     * Their gender.
     */
    profileGender?: 'male' | 'female' | string;
    /**
     * A name inherited from a family or marriage and by which the individual is commonly known.
     */
    profileLastName?: string;
    /**
     * A short unique string to identify them.
     */
    profileUsername?: string;
}
interface MetaFlat extends MetaFlatArticle, MetaFlatBook, MetaFlatProfile {
    /**
     * This attribute declares the document's character encoding.
     * If the attribute is present, its value must be an ASCII case-insensitive match for the string "utf-8",
     * because UTF-8 is the only valid encoding for HTML5 documents.
     * `<meta>` elements which declare a character encoding must be located entirely within the first 1024 bytes
     * of the document.
     *
     * @see https://developer.mozilla.org/en-US/docs/Web/HTML/Element/meta#attr-charset
     */
    charset: 'utf-8' | (string & Record<never, never>);
    /**
     * Use this tag to provide a short description of the page.
     * In some situations, this description is used in the snippet shown in search results.
     *
     * @see https://developers.google.com/search/docs/advanced/appearance/snippet#meta-descriptions
     */
    description: string;
    /**
     * Specifies one or more color schemes with which the document is compatible.
     * The browser will use this information in tandem with the user's browser or device settings to determine what colors
     * to use for everything from background and foregrounds to form controls and scrollbars.
     * The primary use for `<meta name="color-scheme">` is to indicate compatibility with—and order of preference
     * for—light and dark color modes.
     *
     * @see https://developer.mozilla.org/en-US/docs/Web/HTML/Element/meta/name#normal
     */
    colorScheme: 'normal' | 'light dark' | 'dark light' | 'only light' | (string & Record<never, never>);
    /**
     * The name of the application running in the web page.
     *
     * Uses:
     * - When adding the page to the home screen.
     *
     * @see https://developer.mozilla.org/en-US/docs/Web/HTML/Element/meta/name
     */
    applicationName: string;
    /**
     * The name of the document's author.
     *
     * @see https://developer.mozilla.org/en-US/docs/Web/HTML/Element/meta/name
     */
    author: string;
    /**
     * The name of the creator of the document, such as an organization or institution.
     *
     * @see https://developer.mozilla.org/en-US/docs/Web/HTML/Element/meta/name#other_metadata_names
     */
    creator: string;
    /**
     * The name of the document's publisher.
     *
     * @see https://developer.mozilla.org/en-US/docs/Web/HTML/Element/meta/name#other_metadata_names
     */
    publisher: string;
    /**
     * The identifier of the software that generated the page.
     *
     * @see https://developer.mozilla.org/en-US/docs/Web/HTML/Element/meta/name#standard_metadata_names_defined_in_the_html_specification
     */
    generator: string;
    /**
     * Controls the HTTP Referer header of requests sent from the document.
     *
     * @see https://developer.mozilla.org/en-US/docs/Web/HTML/Element/meta/name#standard_metadata_names_defined_in_the_html_specification
     */
    referrer: ReferrerPolicy;
    /**
     * This tag tells the browser how to render a page on a mobile device.
     * Presence of this tag indicates to Google that the page is mobile friendly.
     *
     * @see https://developer.mozilla.org/en-US/docs/Web/HTML/Element/meta/name#standard_metadata_names_defined_in_other_specifications
     */
    viewport: 'width=device-width, initial-scale=1.0' | string | Partial<{
        /**
         * Defines the pixel width of the viewport that you want the web site to be rendered at.
         */
        width: number | string | 'device-width';
        /**
         * Defines the height of the viewport. Not used by any browser.
         */
        height: number | string | 'device-height';
        /**
         * Defines the ratio between the device width
         * (device-width in portrait mode or device-height in landscape mode) and the viewport size.
         *
         * @minimum 0
         * @maximum 10
         */
        initialScale: '1.0' | number | (string & Record<never, never>);
        /**
         * Defines the maximum amount to zoom in.
         * It must be greater or equal to the minimum-scale or the behavior is undefined.
         * Browser settings can ignore this rule and iOS10+ ignores it by default.
         *
         * @minimum 0
         * @maximum 10
         */
        maximumScale: number | string;
        /**
         * Defines the minimum zoom level. It must be smaller or equal to the maximum-scale or the behavior is undefined.
         * Browser settings can ignore this rule and iOS10+ ignores it by default.
         *
         * @minimum 0
         * @maximum 10
         */
        minimumScale: number | string;
        /**
         * If set to no, the user is unable to zoom in the webpage.
         * The default is yes. Browser settings can ignore this rule, and iOS10+ ignores it by default.
         */
        userScalable: 'yes' | 'no';
        /**
         * The auto value doesn't affect the initial layout viewport, and the whole web page is viewable.
         *
         * The contain value means that the viewport is scaled to fit the largest rectangle inscribed within the display.
         *
         * The cover value means that the viewport is scaled to fill the device display.
         * It is highly recommended to make use of the safe area inset variables to ensure that important content
         * doesn't end up outside the display.
         */
        viewportFit: 'auto' | 'contain' | 'cover';
    }>;
    /**
     * Control the behavior of search engine crawling and indexing.
     *
     * @see https://developers.google.com/search/docs/crawling-indexing/robots-meta-tag
     */
    robots: 'noindex, nofollow' | 'index, follow' | string | Partial<{
        /**
         * Allow search engines to index this page.
         *
         * Note: This is not officially supported by Google but is used widely.
         */
        index: Booleanable;
        /**
         * Allow search engines to follow links on this page.
         *
         * Note: This is not officially supported by Google but is used widely.
         */
        follow: Booleanable;
        /**
         * There are no restrictions for indexing or serving.
         * This directive is the default value and has no effect if explicitly listed.
         */
        all: Booleanable;
        /**
         * Do not show this page, media, or resource in search results.
         * If you don't specify this directive, the page, media, or resource may be indexed and shown in search results.
         */
        noindex: Booleanable;
        /**
         * Do not follow the links on this page.
         * If you don't specify this directive, Google may use the links on the page to discover those linked pages.
         */
        nofollow: Booleanable;
        /**
         * Equivalent to noindex, nofollow.
         */
        none: Booleanable;
        /**
         * Do not show a cached link in search results.
         * If you don't specify this directive,
         * Google may generate a cached page and users may access it through the search results.
         */
        noarchive: Booleanable;
        /**
         * Do not show a sitelinks search box in the search results for this page.
         * If you don't specify this directive, Google may generate a search box specific to your site in search results,
         * along with other direct links to your site.
         */
        nositelinkssearchbox: Booleanable;
        /**
         *
         * Do not show a text snippet or video preview in the search results for this page.
         * A static image thumbnail (if available) may still be visible, when it results in a better user experience.
         */
        nosnippet: Booleanable;
        /**
         * Google is allowed to index the content of a page if it's embedded in another
         * page through iframes or similar HTML tags, in spite of a noindex directive.
         *
         * indexifembedded only has an effect if it's accompanied by noindex.
         */
        indexifembedded: Booleanable;
        /**
         * Use a maximum of [number] characters as a textual snippet for this search result.
         */
        maxSnippet: number | string;
        /**
         * Set the maximum size of an image preview for this page in a search results.
         */
        maxImagePreview: 'none' | 'standard' | 'large';
        /**
         * Use a maximum of [number] seconds as a video snippet for videos on this page in search results.
         */
        maxVideoPreview: number | string;
        /**
         * Don't offer translation of this page in search results.
         */
        notranslate: Booleanable;
        /**
         * Do not show this page in search results after the specified date/time.
         */
        unavailable_after: string;
        /**
         * Do not index images on this page.
         */
        noimageindex: Booleanable;
    }>;
    /**
     * Special meta tag for controlling Google's indexing behavior.
     *
     * @see https://developers.google.com/search/docs/crawling-indexing/special-tags
     */
    google: 
    /**
     * When users search for your site, Google Search results sometimes display a search box specific to your site,
     * along with other direct links to your site. This tag tells Google not to show the sitelinks search box.
     */
    'nositelinkssearchbox' | 
    /**
     * Prevents various Google text-to-speech services from reading aloud web pages using text-to-speech (TTS).
     */
    'nopagereadaloud';
    /**
     * Control how Google indexing works specifically for the googlebot crawler.
     *
     * @see https://developers.google.com/search/docs/crawling-indexing/robots-meta-tag
     */
    googlebot: 
    /**
     * When Google recognizes that the contents of a page aren't in the language that the user likely wants to read,
     * Google may provide a translated title link and snippet in search results.
     */
    'notranslate' | 'noimageindex' | 'noarchive' | 'nosnippet' | 'max-snippet' | 'max-image-preview' | 'max-video-preview';
    /**
     * Control how Google indexing works specifically for the googlebot-news crawler.
     *
     * @see https://developers.google.com/search/docs/crawling-indexing/robots-meta-tag
     */
    googlebotNews: 'noindex' | 'nosnippet' | 'notranslate' | 'noimageindex';
    /**
     * You can use this tag on the top-level page of your site to verify ownership for Search Console.
     *
     * @see https://developers.google.com/search/docs/crawling-indexing/special-tags
     */
    googleSiteVerification: string;
    /**
     * Labels a page as containing adult content, to signal that it be filtered by SafeSearch results
     * .
     * @see https://developers.google.com/search/docs/advanced/guidelines/safesearch
     */
    rating: 'adult';
    /**
     * The canonical URL for your page.
     *
     * This should be the undecorated URL, without session variables, user identifying parameters, or counters.
     * Likes and Shares for this URL will aggregate at this URL.
     *
     * For example: mobile domain URLs should point to the desktop version of the URL as the canonical URL to aggregate
     * Likes and Shares across different versions of the page.
     *
     * @see https://ogp.me/#metadata
     */
    ogUrl: string;
    /**
     * The title of your page without any branding such as your site name.
     *
     * @see https://ogp.me/#metadata
     */
    ogTitle: string;
    /**
     * A brief description of the content, usually between 2 and 4 sentences.
     *
     * @see https://ogp.me/#optional
     */
    ogDescription: string;
    /**
     * The type of media of your content. This tag impacts how your content shows up in Feed. If you don't specify a type,
     * the default is website.
     * Each URL should be a single object, so multiple og:type values are not possible.
     *
     * @see https://ogp.me/#metadata
     */
    ogType: 'website' | 'article' | 'book' | 'profile' | 'music.song' | 'music.album' | 'music.playlist' | 'music.radio_status' | 'video.movie' | 'video.episode' | 'video.tv_show' | 'video.other';
    /**
     * The locale of the resource. Defaults to en_US.
     *
     * @see https://ogp.me/#optional
     */
    ogLocale: string;
    /**
     * An array of other locales this page is available in.
     *
     * @see https://ogp.me/#optional
     */
    ogLocaleAlternate: Arrayable<string>;
    /**
     * The word that appears before this object's title in a sentence.
     * An enum of (a, an, the, "", auto).
     * If auto is chosen, the consumer of your data should choose between "a" or "an".
     * Default is "" (blank).
     *
     * @see https://ogp.me/#optional
     */
    ogDeterminer: 'a' | 'an' | 'the' | '' | 'auto';
    /**
     * If your object is part of a larger website, the name which should be displayed for the overall site. e.g., "IMDb".
     *
     * @see https://ogp.me/#optional
     */
    ogSiteName: string;
    /**
     * The URL for the video. If you want the video to play in-line in Feed, you should use the https:// URL if possible.
     *
     * @see https://ogp.me/#type_video
     */
    ogVideo: string | Arrayable<{
        /**
         * Equivalent to og:video
         */
        url: string;
        /**
         *
         * Secure URL for the video. Include this even if you set the secure URL in og:video.
         */
        secureUrl?: string;
        /**
         * MIME type of the video.
         */
        type?: 'application/x-shockwave-flash' | 'video/mp4';
        /**
         * Width of video in pixels. This property is required for videos.
         */
        width?: string | number;
        /**
         * Height of video in pixels. This property is required for videos.
         */
        height?: string | number;
        /**
         * A text description of the video.
         */
        alt?: string;
    }>;
    /**
     * Equivalent to og:video
     *
     * @see https://ogp.me/#type_video
     */
    ogVideoUrl: string;
    /**
     *
     * Secure URL for the video. Include this even if you set the secure URL in og:video.
     *
     * @see https://ogp.me/#type_video
     */
    ogVideoSecureUrl: string;
    /**
     * MIME type of the video.
     *
     * @see https://ogp.me/#type_video
     */
    ogVideoType: 'application/x-shockwave-flash' | 'video/mp4';
    /**
     * Width of video in pixels. This property is required for videos.
     *
     * @see https://ogp.me/#type_video
     */
    ogVideoWidth: string | number;
    /**
     * Height of video in pixels. This property is required for videos.
     *
     * @see https://ogp.me/#type_video
     */
    ogVideoHeight: string | number;
    /**
     * A text description of the video.
     *
     * @see https://ogp.me/#type_video
     */
    ogVideoAlt: string;
    /**
     * The URL of the image that appears when someone shares the content.
     *
     * @see https://developers.facebook.com/docs/sharing/webmasters#images
     */
    ogImage: string | Arrayable<{
        /**
         * Equivalent to og:image
         */
        url: string;
        /**
         *
         * https:// URL for the image
         */
        secureUrl?: string;
        /**
         * MIME type of the image.
         */
        type?: 'image/jpeg' | 'image/gif' | 'image/png';
        /**
         * Width of image in pixels. Specify height and width for your image to ensure that the image loads properly the first time it's shared.
         */
        width?: '1200' | string | number;
        /**
         * Height of image in pixels. Specify height and width for your image to ensure that the image loads properly the first time it's shared.
         */
        height?: '630' | string | number;
        /**
         * A description of what is in the image (not a caption). If the page specifies an og:image, it should specify og:image:alt.
         */
        alt?: string;
    }>;
    /**
     * Equivalent to og:image
     *
     * @see https://developers.facebook.com/docs/sharing/webmasters#images
     */
    ogImageUrl: string;
    /**
     *
     * https:// URL for the image
     *
     * @see https://developers.facebook.com/docs/sharing/webmasters#images
     */
    ogImageSecureUrl: string;
    /**
     * MIME type of the image.
     *
     * @see https://developers.facebook.com/docs/sharing/webmasters#images
     */
    ogImageType: 'image/jpeg' | 'image/gif' | 'image/png';
    /**
     * Width of image in pixels. Specify height and width for your image to ensure that the image loads properly the first time it's shared.
     *
     * @see https://developers.facebook.com/docs/sharing/webmasters#images
     */
    ogImageWidth: '1200' | string | number;
    /**
     * Height of image in pixels. Specify height and width for your image to ensure that the image loads properly the first time it's shared.
     *
     * @see https://developers.facebook.com/docs/sharing/webmasters#images
     */
    ogImageHeight: '630' | string | number;
    /**
     * A description of what is in the image (not a caption). If the page specifies an og:image, it should specify og:image:alt.
     *
     * @see https://developers.facebook.com/docs/sharing/webmasters#images
     */
    ogImageAlt: string;
    /**
     * The URL for an audio file to accompany this object.
     *
     * @see https://ogp.me/#optional
     */
    ogAudio: string | Arrayable<{
        /**
         * Equivalent to og:audio
         */
        url: string;
        /**
         * Secure URL for the audio. Include this even if you set the secure URL in og:audio.
         */
        secureUrl?: string;
        /**
         * MIME type of the audio.
         */
        type?: 'audio/mpeg' | 'audio/ogg' | 'audio/wav';
    }>;
    /**
     * Equivalent to og:audio
     *
     * @see https://ogp.me/#optional
     */
    ogAudioUrl: string;
    /**
     * Secure URL for the audio. Include this even if you set the secure URL in og:audio.
     *
     * @see https://ogp.me/#optional
     */
    ogAudioSecureUrl: string;
    /**
     * MIME type of the audio.
     *
     * @see https://ogp.me/#optional
     */
    ogAudioType: 'audio/mpeg' | 'audio/ogg' | 'audio/wav';
    /**
     * Your Facebook app ID.
     *
     * In order to use Facebook Insights you must add the app ID to your page.
     * Insights lets you view analytics for traffic to your site from Facebook. Find the app ID in your App Dashboard.
     *
     * @see https://developers.facebook.com/docs/sharing/webmasters#basic
     */
    fbAppId: string | number;
    /**
     * The card type
     *
     * Used with all cards
     *
     * @see https://developer.twitter.com/en/docs/twitter-for-websites/cards/overview/abouts-cards
     */
    twitterCard: 'summary' | 'summary_large_image' | 'app' | 'player';
    /**
     * Title of content (max 70 characters)
     *
     * Used with summary, summary_large_image, player cards
     *
     * Same as `og:title`
     *
     * @maxLength 70
     * @see https://developer.twitter.com/en/docs/twitter-for-websites/cards/overview/abouts-cards
     */
    twitterTitle: string;
    /**
     * Description of content (maximum 200 characters)
     *
     * Used with summary, summary_large_image, player cards.
     *
     * Same as `og:description`
     *
     * @maxLength 200
     * @see https://developer.twitter.com/en/docs/twitter-for-websites/cards/overview/abouts-cards
     */
    twitterDescription: string;
    /**
     * URL of image to use in the card.
     * Images must be less than 5MB in size.
     * JPG, PNG, WEBP and GIF formats are supported.
     * Only the first frame of an animated GIF will be used. SVG is not supported.
     *
     * Used with summary, summary_large_image, player cards
     *
     * Same as `og:image`.
     *
     * @see https://developer.twitter.com/en/docs/twitter-for-websites/cards/overview/abouts-cards
     */
    twitterImage: string | Arrayable<{
        /**
         * Equivalent to twitter:image
         */
        url: string;
        /**
         * MIME type of the image.
         * @deprecated Twitter removed this property from their card specification.
         */
        type?: 'image/jpeg' | 'image/gif' | 'image/png';
        /**
         * Width of image in pixels. Specify height and width for your image to ensure that the image loads properly the first time it's shared.
         * @deprecated Twitter removed this property from their card specification.
         */
        width?: '1200' | string | number;
        /**
         * Height of image in pixels. Specify height and width for your image to ensure that the image loads properly the first time it's shared.
         * @deprecated Twitter removed this property from their card specification.
         */
        height?: '630' | string | number;
        /**
         * A description of what is in the image (not a caption). If the page specifies an og:image, it should specify og:image:alt.
         */
        alt?: string;
    }>;
    /**
     * The width of the image in pixels.
     *
     * Note: This is not officially documented.
     *
     * Same as `og:image:width`
     *
     * @deprecated Twitter removed this property from their card specification.
     * @see https://developer.twitter.com/en/docs/twitter-for-websites/cards/overview/abouts-cards
     */
    twitterImageWidth: string | number;
    /**
     * The height of the image in pixels.
     *
     * Note: This is not officially documented.
     *
     * Same as `og:image:height`
     *
     * @deprecated Twitter removed this property from their card specification.
     * @see https://developer.twitter.com/en/docs/twitter-for-websites/cards/overview/abouts-cards
     */
    twitterImageHeight: string | number;
    /**
     * The type of the image.
     *
     * Note: This is not officially documented.
     *
     * Same as `og:image:type`
     *
     * @deprecated Twitter removed this property from their card specification.
     * @see https://developer.twitter.com/en/docs/twitter-for-websites/cards/overview/abouts-cards
     */
    twitterImageType: 'image/jpeg' | 'image/gif' | 'image/png';
    /**
     * A text description of the image conveying the essential nature of an image to users who are visually impaired.
     * Maximum 420 characters.
     *
     * Used with summary, summary_large_image, player cards
     *
     * Same as `og:image:alt`.
     *
     * @maxLength 420
     * @see https://developer.twitter.com/en/docs/twitter-for-websites/cards/overview/abouts-cards
     */
    twitterImageAlt: string;
    /**
     * The @username of website. Either twitter:site or twitter:site:id is required.
     *
     * Used with summary, summary_large_image, app, player cards
     *
     * @example @harlan_zw
     * @see https://developer.twitter.com/en/docs/twitter-for-websites/cards/overview/markup
     */
    twitterSite: string;
    /**
     * Same as twitter:site, but the user’s Twitter ID. Either twitter:site or twitter:site:id is required.
     *
     * Used with summary, summary_large_image, player cards
     *
     * @example 1296047337022742529
     * @see https://developer.twitter.com/en/docs/twitter-for-websites/cards/overview/markup
     */
    twitterSiteId: string | number;
    /**
     * The @username who created the pages content.
     *
     * Used with summary_large_image cards
     *
     * @example harlan_zw
     * @see https://developer.twitter.com/en/docs/twitter-for-websites/cards/overview/markup
     */
    twitterCreator: string;
    /**
     * Twitter user ID of content creator
     *
     * Used with summary, summary_large_image cards
     *
     * @see https://developer.twitter.com/en/docs/twitter-for-websites/cards/overview/markup
     */
    twitterCreatorId: string | number;
    /**
     * HTTPS URL of player iframe
     *
     * Used with player card
     *
     * @see https://developer.twitter.com/en/docs/twitter-for-websites/cards/overview/markup
     */
    twitterPlayer: string;
    /**
     *
     * Width of iframe in pixels
     *
     * Used with player card
     *
     * @see https://developer.twitter.com/en/docs/twitter-for-websites/cards/overview/markup
     */
    twitterPlayerWidth: string | number;
    /**
     * Height of iframe in pixels
     *
     * Used with player card
     *
     * @see https://developer.twitter.com/en/docs/twitter-for-websites/cards/overview/markup
     */
    twitterPlayerHeight: string | number;
    /**
     * URL to raw video or audio stream
     *
     * Used with player card
     *
     * @see https://developer.twitter.com/en/docs/twitter-for-websites/cards/overview/markup
     */
    twitterPlayerStream: string;
    /**
     * Name of your iPhone app
     *
     * Used with app card
     *
     * @see https://developer.twitter.com/en/docs/twitter-for-websites/cards/overview/markup
     */
    twitterAppNameIphone: string;
    /**
     * Your app ID in the iTunes App Store
     *
     * Used with app card
     *
     * @see https://developer.twitter.com/en/docs/twitter-for-websites/cards/overview/markup
     */
    twitterAppIdIphone: string;
    /**
     * Your app’s custom URL scheme (you must include ”://” after your scheme name)
     *
     * Used with app card
     *
     * @see https://developer.twitter.com/en/docs/twitter-for-websites/cards/overview/markup
     */
    twitterAppUrlIphone: string;
    /**
     * Name of your iPad optimized app
     *
     * Used with app card
     *
     * @see https://developer.twitter.com/en/docs/twitter-for-websites/cards/overview/markup
     */
    twitterAppNameIpad: string;
    /**
     * Your app ID in the iTunes App Store
     *
     * Used with app card
     *
     * @see https://developer.twitter.com/en/docs/twitter-for-websites/cards/overview/markup
     */
    twitterAppIdIpad: string;
    /**
     * Your app’s custom URL scheme
     *
     * Used with app card
     *
     * @see https://developer.twitter.com/en/docs/twitter-for-websites/cards/overview/markup
     */
    twitterAppUrlIpad: string;
    /**
     * Name of your Android app
     *
     * Used with app card
     *
     * @see https://developer.twitter.com/en/docs/twitter-for-websites/cards/overview/markup
     */
    twitterAppNameGoogleplay: string;
    /**
     * Your app ID in the Google Play Store
     *
     * Used with app card
     *
     * @see https://developer.twitter.com/en/docs/twitter-for-websites/cards/overview/markup
     */
    twitterAppIdGoogleplay: string;
    /**
     * Your app’s custom URL scheme
     *
     * @see https://developer.twitter.com/en/docs/twitter-for-websites/cards/overview/markup
     */
    twitterAppUrlGoogleplay: string;
    /**
     * Top customizable data field, can be a relatively short string (ie “$3.99”)
     *
     * Used by Slack.
     *
     * @see https://api.slack.com/reference/messaging/link-unfurling#classic_unfurl
     */
    twitterData1: string;
    /**
     * Customizable label or units for the information in twitter:data1 (best practice: use all caps)
     *
     * Used by Slack.
     *
     * @see https://api.slack.com/reference/messaging/link-unfurling#classic_unfurl
     */
    twitterLabel1: string;
    /**
     * Bottom customizable data field, can be a relatively short string (ie “Seattle, WA”)
     *
     * Used by Slack.
     *
     * @see https://api.slack.com/reference/messaging/link-unfurling#classic_unfurl
     */
    twitterData2: string;
    /**
     * Customizable label or units for the information in twitter:data2 (best practice: use all caps)
     *
     * Used by Slack.
     *
     * @see https://api.slack.com/reference/messaging/link-unfurling#classic_unfurl
     */
    twitterLabel2: string;
    /**
     * Indicates a suggested color that user agents should use to customize the display of the page or
     * of the surrounding user interface.
     *
     * @see https://developer.mozilla.org/en-US/docs/Web/HTML/Element/meta/name
     * @example `#4285f4` or `{ color: '#4285f4', media: '(prefers-color-scheme: dark)'}`
     */
    themeColor: string | Arrayable<{
        /**
         * A valid CSS color value that matches the value used for the `theme-color` CSS property.
         *
         * @example `#4285f4`
         */
        content: string;
        /**
         * A valid media query that defines when the value should be used.
         *
         * @example `(prefers-color-scheme: dark)`
         */
        media: '(prefers-color-scheme: dark)' | '(prefers-color-scheme: light)' | string;
    }>;
    /**
     * Sets whether a web application runs in full-screen mode.
     */
    mobileWebAppCapable: 'yes';
    /**
     * Sets whether a web application runs in full-screen mode.
     *
     * @see https://developer.apple.com/library/archive/documentation/AppleApplications/Reference/SafariHTMLRef/Articles/MetaTags.html
     */
    appleMobileWebAppCapable: 'yes';
    /**
     * Sets the style of the status bar for a web application.
     *
     * @see https://developer.apple.com/library/archive/documentation/AppleApplications/Reference/SafariHTMLRef/Articles/MetaTags.html
     */
    appleMobileWebAppStatusBarStyle: 'default' | 'black' | 'black-translucent';
    /**
     * Make the app title different from the page title.
     */
    appleMobileWebAppTitle: string;
    /**
     * Promoting Apps with Smart App Banners
     *
     * @see https://developer.apple.com/documentation/webkit/promoting_apps_with_smart_app_banners
     */
    appleItunesApp: string | {
        /**
         * Your app’s unique identifier.
         */
        appId: string;
        /**
         * A URL that provides context to your native app.
         */
        appArgument?: string;
    };
    /**
     * Enables or disables automatic detection of possible phone numbers in a webpage in Safari on iOS.
     *
     * @see https://developer.apple.com/library/archive/documentation/AppleApplications/Reference/SafariHTMLRef/Articles/MetaTags.html
     */
    formatDetection: 'telephone=no';
    /**
     * Tile image for windows.
     *
     * @see https://learn.microsoft.com/en-us/previous-versions/windows/internet-explorer/ie-developer/platform-apis/dn320426(v=vs.85)
     */
    msapplicationTileImage: string;
    /**
     * Tile colour for windows
     *
     * @see https://learn.microsoft.com/en-us/previous-versions/windows/internet-explorer/ie-developer/platform-apis/dn320426(v=vs.85)
     */
    msapplicationTileColor: string;
    /**
     * URL of a config for windows tile.
     *
     * @see https://learn.microsoft.com/en-us/previous-versions/windows/internet-explorer/ie-developer/platform-apis/dn320426(v=vs.85)
     */
    msapplicationConfig: string;
    contentSecurityPolicy: string | Partial<{
        childSrc: string;
        connectSrc: string;
        defaultSrc: string;
        fontSrc: string;
        imgSrc: string;
        manifestSrc: string;
        mediaSrc: string;
        objectSrc: string;
        prefetchSrc: string;
        scriptSrc: string;
        scriptSrcElem: string;
        scriptSrcAttr: string;
        styleSrc: string;
        styleSrcElem: string;
        styleSrcAttr: string;
        workerSrc: string;
        baseUri: string;
        sandbox: string;
        formAction: string;
        frameAncestors: string;
        reportUri: string;
        reportTo: string;
        requireSriFor: string;
        requireTrustedTypesFor: string;
        trustedTypes: string;
        upgradeInsecureRequests: string;
    }>;
    contentType: 'text/html; charset=utf-8';
    defaultStyle: string;
    xUaCompatible: 'IE=edge';
    refresh: string | {
        seconds: number | string;
        url: string;
    };
    /**
     * A comma-separated list of keywords - relevant to the page (Legacy tag used to tell search engines what the page is about).
     * @deprecated the "keywords" metatag is no longer used.
     * @see https://web.dev/learn/html/metadata/#keywords
     */
    keywords: string;
}
type MetaFlatNullable = {
    [K in keyof MetaFlat]: MetaFlat[K] | null;
};
type MetaFlatInput = Partial<MetaFlatNullable>;
type AsyncMetaFlatInput = MaybePromiseProps<MetaFlatInput>;

export type { AsyncMetaFlatInput as A, Booleanable as B, DataKeys as D, MaybePromiseProps as M, ReferrerPolicy as R, Stringable as S, MergeHead as a, Merge as b, DefinedValueOrEmptyObject as c, MetaFlatArticle as d, MetaFlatBook as e, MetaFlatProfile as f, MetaFlat as g, MetaFlatInput as h, Arrayable as i };
