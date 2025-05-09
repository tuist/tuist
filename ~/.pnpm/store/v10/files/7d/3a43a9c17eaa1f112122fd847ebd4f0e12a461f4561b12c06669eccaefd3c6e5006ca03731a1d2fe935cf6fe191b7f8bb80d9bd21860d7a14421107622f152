export = CookieConsent
export as namespace CookieConsent

declare namespace CookieConsent {

    type AcceptType =
        'all'
        | 'custom'
        | 'necessary'

    type ConsentModalLayout =
        'box'
        | 'box wide'
        | 'box inline'
        | 'cloud'
        | 'cloud inline'
        | 'bar'
        | 'bar inline'

    type ConsentModalPosition =
        'top'
        | 'bottom'
        | 'middle'
        | 'top left'
        | 'top center'
        | 'top right'
        | 'middle left'
        | 'middle center'
        | 'middle right'
        | 'bottom left'
        | 'bottom center'
        | 'bottom right'

    type PreferencesModalLayout =
        'box'
        | 'bar'
        | 'bar wide'

    type PreferencesModalPosition = 'left' | 'right'

    type ModalName = 'consentModal' | 'preferencesModal'

    /**
     * Cookie to clear
     */
    interface CookieItem {
        /**
         * Cookie name
         */
        name: string | RegExp

        /**
         * Expected cookie path
         */
        path?: string

        /**
         * Expected cookie domain. Useful if you want to erase
         * a cookie set in the main domain, from the subdomain.
         */
        domain?: string
    }

    interface AutoClear {
        /**
         * Array of cookies to clear.
         */
        cookies: CookieItem[]

        /**
         * Reload page after the autoClear function.
         *
         * @default false
         */
        reloadPage?: boolean
    }

    interface Service {
        /**
         * Custom visible label (can also be html markup).
         */
        label?: string

        /**
         * Callback executed when the service is accepted.
         */
        onAccept?: () => void

        /**
         * Callback executed when the service is rejected
         * (assuming that it was previously enabled).
         */
        onReject?: () => void,

        /**
         * Array of cookies to clear.
         */
        cookies?: CookieItem[]
    }

    interface UserPreferences {
        /**
         * - all: all categories were accepted
         * - necessary: only the necessary (if any) categories were accepted
         * - custom: a custom selection of categories was accepted
         */
        acceptType: AcceptType

        acceptedCategories: string[]
        rejectedCategories: string[]

        acceptedServices: {[key: string]: string[]}
        rejectedServices: {[key: string]: string[]}
    }

    interface Category {
        /**
         * Mark category as enabled by default.
         *
         * If mode is set to `'opt-out'` and consent has not yet been expressed, the category
         * is automatically enabled (and scripts under this category will be executed).
         *
         * @default false
         */
        enabled?: boolean

        /**
         * Treat the category as necessary. The user won't be able to disable the category.
         *
         * @default false
         */
        readOnly?: boolean

        /**
         * Configure individually togglable services.
         */
        services?: {[key: string]: Service}

        /**
         * Declare the cookies to erase when the user rejects the category.
         */
        autoClear?: AutoClear
    }

    interface CookieValue {
        /**
         * All accepted categories.
         */
        categories: string[]

        /**
         * Last accepted revision number.
         *
         * @default 0
         */
        revision: number

        /**
         * Used to store custom data.
         */
        data: any

        /**
         * Unique UUIDV4 string that identifies the current user.
         */
        consentId: string

        /**
         * User's first consent timestamp.
         */
        consentTimestamp: string

        /**
         * User's last consent update.
         */
        lastConsentTimestamp: string

        /**
         * Language code of the consent.
         */
        languageCode: string

        /**
         * All enabled services.
         */
        services: {[key: string]: string[]}

        /**
         * Expiration time of the cookie (in case localstorage is used)
         */
        expirationTime: number
    }

    interface CookieOptions {
        /**
         * Cookie name.
         *
         * @default 'cc_cookie'
         */
        name?: string

        /**
         * Cookie domain.
         *
         * @default location.hostname
         */
        domain?: string

        /**
         * Cookie path.
         *
         * @default '/'
         */
        path?: string

        /**
         * Cookie sameSite.
         *
         * @default 'Lax'
         */
        sameSite?: 'Lax' | 'Strict' | 'None'

        /**
         * Cookie secure flag.
         *
         * @default true
         */
        secure?: boolean

        /**
         * Cookie duration.
         *
         * @default 182
         */
        expiresAfterDays?: number | ((acceptType: AcceptType) => number)

        /**
         * Store the content of the cookie in localstorage
         *
         * @default false
         */
        useLocalStorage?: boolean
    }

    interface GuiOptions {
        consentModal?: {
            /**
             * Change consentModal layout.
             *
             * @default 'box'
             */
            layout?: ConsentModalLayout

            /**
             * Change modal position.
             */
            position?: ConsentModalPosition

            /**
             * Flip buttons.
             *
             * @default false
             */
            flipButtons?: boolean

            /**
             * Stylize the accept and reject buttons the same way (GDPR compliant).
             *
             * @default true
             */
            equalWeightButtons?: boolean
        }
        preferencesModal?: {

            /**
             * Change preferencesModal layout.
             */
            layout?: PreferencesModalLayout

            /**
             * This options is valid only if layout=bar.
             */
            position?: PreferencesModalPosition

            /**
             * Flip buttons.
             * @default false
             */
            flipButtons?: boolean

            /**
             * Stylize the accept and reject buttons the same way (GDPR compliant).
             *
             * @default true
             */
            equalWeightButtons?: boolean
        }
    }

    interface ConsentModalOptions {

        /**
         * Accessibility label. Especially useful if no title is provided.
         */
        label?: string

        title?: string
        description?: string
        acceptAllBtn?: string
        acceptNecessaryBtn?: string
        showPreferencesBtn?: string

        /**
         * Specify to generate a big "X" (accept necessary) button. Visible in the `box` layout only.
         */
        closeIconLabel?: string

        /**
         * Set a revision message, visible when the revision number changes.
         * Check out the [docs](https://cookieconsent.orestbida.com/advanced/revision-management.html) for more.
         */
        revisionMessage?: string

        /**
         * Custom HTML string where you can put links pointing to your privacy policy.
         */
        footer?: string
    }

    interface CookieTable {

        /**
         * Table caption
         */
        caption?: string,

        /**
         * Define the table headers (columns).
         */
        headers: {[key: string]: string}

        /**
         * Define the table body items (rows).
         */
        body: {[key: string]: string}[]
    }

    interface Section {
        /**
         * Section title.
         */
        title?: string

        /**
         * Section description.
         */
        description?: string

        /**
         * Name of a valid category. This will convert the current section into a "togglable" category.
         */
        linkedCategory?: string

        /**
         * Create a custom html table (generally used to clarify cookies).
         */
        cookieTable?: CookieTable
    }

    interface PreferencesModalOptions {
        title?: string
        acceptAllBtn?: string
        acceptNecessaryBtn?: string
        savePreferencesBtn?: string

        /**
         * Accessibility label.
         */
        closeIconLabel?: string

        /**
         * Label to append to services counter.
         */
        serviceCounterLabel?: string

        sections: Section[]
    }

    interface Translation {
        consentModal: ConsentModalOptions
        preferencesModal: PreferencesModalOptions
    }

    interface CookieConsentConfig {
        /**
         * Root element where the modal will be appended.
         *
         * @default document.body
         */
        root?: string | Element | null

        /**
         * Check out the [docs](https://cookieconsent.orestbida.com/reference/configuration-reference.html#mode) for details.
         *
         * @default 'opt-in'
         */
        mode?: 'opt-in' | 'opt-out'

        /**
         * Automatically show the consentModal if consent is not valid.
         *
         * @default true
         */
        autoShow?: boolean

        /**
         * Manage revisions. Check out the [docs](https://cookieconsent.orestbida.com/reference/configuration-reference.html#revision) for details and examples.
         *
         * @default 0
         */
        revision?: number

        /**
         * Intercept script tags with a "data-category" attribute.
         *
         * @default true
         */
        manageScriptTags?: boolean

        /**
         * Automatically erase cookies when the user opts-out of a category.
         * Check out the [docs](https://cookieconsent.orestbida.com/reference/configuration-reference.html#categories-autoclear).
         *
         * @default true
         */
        autoClearCookies?: boolean

        /**
         * Create dark overlay and disable page scroll until consent.
         *
         * @default false
         */
        disablePageInteraction?: boolean

        /**
         * Stop the plugin's execution if a bot/crawler is detected
         * to prevent the indexing of the modal's content.
         *
         * @default true
         */
        hideFromBots?: boolean

        /**
         * Tweak some UI options.
         */
        guiOptions?: GuiOptions

        /**
         * Generates the modals on the fly
         * and only if needed
         *
         * @default true
         */
        lazyHtmlGeneration?: boolean

        /**
         * Change plugin's default cookie options.
         */
        cookie?: CookieOptions

        /**
         * Callback fired on the very first consent action.
         */
        onFirstConsent?: (param: {
            cookie: CookieValue
        }) => void

        /**
         * Callback fired on the very first consent action
         * and on each page load.
         */
        onConsent?: (param: {
            cookie: CookieValue
        }) => void

        /**
         * Callback fired when categories or services are changed.
         */
        onChange?: (param: {
            cookie: CookieValue
            changedCategories: string[],
            changedServices: {[key: string]: string[]}
        }) => void

        /**
         * Callback fired when one of the modals is visible.
         */
        onModalShow?: (param: {
            modalName: ModalName
        }) => void

        /**
         * Callback fired when one of the modals is hidden.
         */
        onModalHide?: (param: {
            modalName: ModalName
        }) => void

        /**
         * Callback fired when one of the modals is appended to the dom.
         */
        onModalReady?: (param: {
            modalName: ModalName,
            modal: HTMLElement
        }) => void

        /**
         * Configure cookie categories.
         */
        categories: {[key: string]: Category}

        /**
         * Configure language and translations.
         */
        language: {
            /**
             * Default language.
             *
             * E.g. 'en'
             */
            default: string,

            /**
             * RTL language(s).
             */
            rtl?: string | string[]

            /**
             * Language detection strategy.
             */
            autoDetect?: 'document' | 'browser'

            translations: {
                [locale: string]: Translation
                | string
                | (() => Translation)
                | (() => Promise<Translation>)
            }
        }
    }


    /**
     * Configure and run the plugin.
     */
    function run(configOptions: CookieConsentConfig): Promise<void>

    /**
     * Show the consentModal.
     *
     * Pass the argument 'true' (boolean) to generate the modal if it doesn't exist.
     */
    function show(createModal?: boolean): void

    /**
     * Hide the consentModal.
     */
    function hide(): void

    /**
     * Show the preferencesModal.
     */
    function showPreferences(): void

    /**
     * Hide the preferencesModal.
     */
    function hidePreferences(): void

    /**
     * Accept/Reject categories.
     * @param categories Categories to accept
     * @param excludedCategories Categories to exclude
     */
    function acceptCategory(categories: string | string[], excludedCategories?: string[]): void

    /**
     * Accept/Reject services.
     * @param services Services to accept
     * @param category Category where the service is defined
     */
    function acceptService(services: string | string[], category: string): void

    /**
     * Returns true if category is accepted, otherwise false.
     * @param categoryName Name of the category
     * @returns boolean: true if category is accepted
     */
    function acceptedCategory(categoryName: string): boolean

    /**
     * Check if the service in the specified category is accepted.
     * @param serviceName Name of the service
     * @param categoryName Name of the category
     * @returns boolean: true if service is accepted
     */
    function acceptedService(serviceName: string, categoryName: string): boolean

    /**
     * Returns true if consent is valid, otherwise false.
     * @returns boolean: true if category is accepted
     */
    function validConsent(): boolean

    /**
     * Check if cookie is valid (exists and has a non empty value).
     * @param cookieName Name of the cookie
     * @returns boolean: true if cookie is valid
     */
    function validCookie(cookieName: string): boolean

    /**
     * Erase one or multiple cookies.
     * @param cookies Names of the cookies to erase
     * @param path Expected path
     * @param domain Expected domain
     */
    function eraseCookies(cookies: string | RegExp | (string|RegExp)[], path?: string, domain?: string): void

    /**
     * Load '.js' files.
     * @param src Path pointing to the js file
     * @param attributes Attributes added to the script
     * @returns Promise<boolean>: true if script is loaded successfully
     */
    function loadScript(src: string, attributes?: {[key: string]: string}): Promise<boolean>

    /**
     * Store custom data inside plugin's own cookie.
     * @param data Object containing the value to save, and the write method
     * @returns boolean: true on success
     */
    function setCookieData(data: {value: any, mode?: 'overwrite' | 'update'}): boolean

    /**
     * Get the entire cookie object.
     * @returns object with all the cookie fields
     */
    function getCookie(): CookieValue

    /**
     * Get a specific field from the cookie.
     * @param field Cookie field (string)
     * @returns value of the specified field
     */
    function getCookie<Field extends keyof CookieValue>(field: Field): CookieValue[Field]

    /**
     * Get the full config. object.
     * @returns config. object
     */
    function getConfig(): CookieConsentConfig

    /**
     * Get one of the configuration options.
     * @param field Configuration option
     * @returns value of the specified field
     */
    function getConfig<Field extends keyof CookieConsentConfig>(field: Field): CookieConsentConfig[Field]

    /**
     * Retrieve the user's preferences. Useful for logging purposes.
     * @returns object with the user's preferences
     */
    function getUserPreferences(): UserPreferences

    /**
     * Change modal's language. Language must already be declared in the config.
     * @param languageCode desired language
     * @param forceSet forcefully set language and reload modals
     * @returns Promise<boolean>: true if language is set successfully
     */
    function setLanguage(languageCode: string, forceSet?: boolean): Promise<boolean>

    /**
     * Reset cookieconsent.
     * @param eraseCookie delete plugin's cookie
     */
    function reset(eraseCookie?: boolean): void
}

declare global {
    interface Window {
        CookieConsent: typeof CookieConsent
    }
}
