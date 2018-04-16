//
//  Paddle.h
//  Paddle Test
//
//  Created by Louis Harwood on 10/05/2013.
//  Copyright (c) 2016 Paddle. All rights reserved.
//  Version: 3.0.20

#define kPADProductName @"name"
#define kPADOnSale @"on_sale"
#define kPADDiscount @"discount_line"
#define kPADUsualPrice @"base_price"
#define kPADCurrentPrice @"current_price"
#define kPADCurrency @"price_currency"
#define kPADDevName @"vendor_name"
#define kPADTrialText @"text"
#define kPADImage @"image"
#define kPADTrialDuration @"duration"
#define kPADProductImage @"default_image"
#define kPADLicence @"PaddleL"
#define kPADEmail @"PaddleEmail"
#define kPADFirstLaunchDate @"first_launch_date"
#define kPADCouponProduct @"productId"
#define kPADCouponCode @"couponCode"

#define kPADActivated @"Activated"
#define kPADContinue @"Continue"
#define kPADTrialExpired @"TrialExpired"

#define kPADCheckoutEmail @"email"
#define kPADCheckoutCountry @"country"
#define kPADCheckoutZip @"postcode"
#define kPADCheckoutQuantity @"quantity"
#define kPADCheckoutAllowQuantity @"allowQuantity"
#define kPADCheckoutReferrer @"referrer"
#define kPADCheckoutDisableLogout @"disableLogout"
#define kPADCheckoutAuthHash @"auth"
#define kPADCheckoutPriceCurrency @"currency"
#define kPADCheckoutPrice @"price"
#define kPADCheckoutPrices @"prices"
#define kPADCheckoutRecurringPrices @"recurringPrices"

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>

typedef enum licenseTypes
{
    PADActivationLicense,
    PADFeatureLicense
} LicenseType;

@protocol PaddleDelegate <NSObject>

@optional
- (void)licenceActivated;
- (void)licenceDeactivated:(BOOL)deactivated message:(nullable NSString *)deactivateMessage productId:(nonnull NSString *)productId;
- (void)paddleDidFailWithError:(nullable NSError *)error;
- (BOOL)willShowBuyWindow;
- (BOOL)willPresentModalForWindow:(NSWindow * _Nullable )window;
- (void)productDataReceived;
- (BOOL)shouldDestroyLicenceOnVerificationFail;
- (int)failedAttemptsBeforeLicenceDestruction;
- (BOOL)onlyDestroyLicenceOnVerificationFail;
- (nonnull NSString *)appGroupForSharedLicense;
@end

@class PADProductWindowController;
@class PADActivateWindowController;
@class PADBuyWindowController;

@interface Paddle : NSObject {
    PADProductWindowController *productWindow;
    PADActivateWindowController *activateWindow;
    PADBuyWindowController *buyWindow;
    NSWindow *devMainWindow;
    
    BOOL isTimeTrial;
    BOOL isOpen;
    BOOL canForceExit;
    BOOL willShowLicensingWindow;
    BOOL hasTrackingStarted;
    BOOL willSimplifyViews;
    BOOL willShowActivationAlert;
    BOOL willContinueAtTrialEnd;
    BOOL willShowDeactivateLicenceButton;
    BOOL willPromptForEmailToStartTrial;
    
    #if !__has_feature(objc_arc)
    id <PaddleDelegate> delegate;
    #endif
}

@property (nullable, assign) id <PaddleDelegate> delegate;

@property (nullable, nonatomic, retain) PADProductWindowController *productWindow;
@property (nullable, nonatomic, retain) PADActivateWindowController *activateWindow;
@property (nullable, nonatomic, retain) PADBuyWindowController *buyWindow;
@property (nullable, nonatomic, retain) NSWindow *devMainWindow;

/**
 Does the product support Time Trials
 */
@property (assign) BOOL isTimeTrial;

/**
 Are any Paddle/SDK Windows currently visible
 */
@property (assign) BOOL isOpen;

/**
 Should the SDK be allowed to force a hard exit.
 */
@property (assign) BOOL canForceExit;

/**
 Should the Licencing Window be displayed.
 */
@property (assign) BOOL willShowLicensingWindow;

/**
 Is the SDK currently tracking events and recording with Paddle Analytics
 */
@property (assign) BOOL hasTrackingStarted;

/**
 Remove Purchase buttons from Licencing Windows
 */
@property (assign) BOOL willSimplifyViews;

/**
 Should the user see a default confirmation message that a licence has been activated.
 */
@property (assign) BOOL willShowActivationAlert;

/**
 Should a user be able to continue using the app after a time trial has expired (default = NO)
 */
@property (assign) BOOL willContinueAtTrialEnd;

/**
 When viewing an activated licence should a deactivate button be displayed (default = NO)
 */
@property (assign) BOOL willShowDeactivateLicenceButton;

/**
 Should the SDK prompt a user for an email before starting a trial (default = NO)
 */
@property (assign) BOOL willPromptForEmailToStartTrial;

/**
 Should the licence be stored globally for all users on the machine (default = NO)
 */
@property (assign) BOOL isSiteLicensed;

/**
 Should old licences be automatically remotely verified
 */
@property (assign) BOOL shouldAutoVerify;

/**
 Should remove ambiguous licenses when verification has failed
 */
@property (assign) BOOL shouldRemoveAmbiguousLicenses;



+ (nonnull Paddle *)sharedInstance;

/** Sets the Paddle API Key to be used for this application.
 *
 * @param apiKey An NSString containing your API Key.
 */
- (void)setApiKey:(nonnull NSString *)apiKey;

/** Sets the Paddle Vendor ID to be used for this application.
 *
 * @param vendorId An NSString containing your vendor ID.
 */
- (void)setVendorId:(nonnull NSString *)vendorId;

/** Sets the Paddle Product ID to be used for this application.
 *
 * @param productId An NSString containing your product ID.
 */
- (void)setProductId:(nonnull NSString *)productId;


/** Starts the Paddle Licensing process. Displays a window to view product information and trial status if there is one.
 *
 * @param productInfo A dictionary containing product information and trial settings. Used for first run/no internet, data is overwritten with response from Paddle API.
 * @param timeTrial A BOOL to indicate if the licensing process should be started with a time trial or not (feature trial).
 * @param mainWindow An NSWindow the licensing window should be attached as a sheet to if required. Can be nil for licensing to be presented modally.
 */
- (void)startLicensing:(nonnull NSDictionary<NSString *, NSString *> *)productInfo timeTrial:(BOOL)timeTrial withWindow:(nullable NSWindow *)mainWindow;


/** Starts the Paddle Licensing process without displaying any UI.
 *
 * @param productInfo A dictionary containing product information and trial settings. Used for first run/no internet, data is overwritten with response from Paddle API.
 * @param timeTrial A BOOL to indicate if the licensing process should be started with a time trial or not (feature trial).
 */
- (void)startLicensingSilently:(nonnull NSDictionary<NSString *, NSString *> *)productInfo timeTrial:(BOOL)timeTrial;


/** Displays the PurchaseView for your product. One of the startLicensing methods must have been called before this
 */
- (void)startPurchase;

/** Displays the PurchaseView for a product. One of the startLicensing methods must have been called before this
 */
- (void)startPurchaseForChildProduct:(nonnull NSString *)childProductId;

/** Displays the PurchaseView for your product. One of the startLicensing methods must have been called before this
 *
 * @param window An NSWindow the purchase window should be attached as a sheet to if required. Can be nil for this to presented modally..
 * @param completionBlock A block to be called when a purchase has completed, returning the email address used along with the licence code.
 */
- (void)startPurchaseWithWindow:(nullable NSWindow *)window completionBlock:(nullable void (^)( NSString * _Nullable email,  NSString * _Nullable licenceCode, BOOL activate, NSDictionary * _Nullable  checkoutData))completionBlock;

/** Opens the default browser on a purchase page for the product.
 */
- (void)startExternalPurchase;

/** Displays the PurchaseView for any Paddle Product ID
 *
 * @param productId A String containing a Paddle Product ID
 * @param window An NSWindow the purchase window should be attached as a sheet to if required. Can be nil for this to presented modally..
 * @param completionBlock A block to be called when a purchase has completed, returning the email address used along with the licence code. If the product is a subscription product the response will contain an order ID
 */
- (void)purchaseProduct:(nonnull NSString *)productId withWindow:(nullable NSWindow *)window completionBlock:(nonnull void (^)(NSString * _Nullable response, NSString * _Nullable email, BOOL completed, NSError * _Nullable error, NSDictionary * _Nullable checkoutData))completionBlock;

/** Displays the PurchaseView for any Paddle Child Product ID
 *
 * @param childProductId A String containing a Paddle Product ID
 * @param window An NSWindow the purchase window should be attached as a sheet to if required. Can be nil for this to presented modally..
 * @param completionBlock A block to be called when a purchase has completed, returning the email address used along with the licence code. If the product is a subscription product the response will contain an order ID
 */
- (void)purchaseChildProduct:(nonnull NSString *)childProductId withWindow:(nullable NSWindow *)window completionBlock:(nonnull void (^)(NSString * _Nullable response, NSString * _Nullable email, BOOL completed, NSError * _Nullable error, NSDictionary * _Nullable checkoutData))completionBlock;

/** Sets up a feature product (sub product of your main product)
 *
 * @param childProductId A String containing the Paddle Product ID.
 * @param productInfo A dictionary containing product information and trial settings. Used for first run/no internet, data is overwritten with response from Paddle API.
 * @param timeTrial A BOOL indicating if the feature product should be a time limited trial.
 */
- (void)setupChildProduct:(nonnull NSString *)childProductId productInfo:(nonnull NSDictionary<NSString *, NSString *> *)productInfo timeTrial:(BOOL)timeTrial;


/** Returns the number of days remaining on the users trial. Can be a negative number (-20 would indicate the trial ended 20 days ago)
 *
 * @return An NSNumber of the days remaining on the users trial.
 */
- (nonnull NSNumber *)daysRemainingOnTrial;

/** Returns the number of days remaining on the users trial. Can be a negative number (-20 would indicate the trial ended 20 days ago)
 *
 * @param childProductId A string containing the Paddle Product ID
 * @return An NSNumber of the days remaining on the users trial for the product.
 */
- (nonnull NSNumber *)daysRemainingOnTrialForChildProduct:(nonnull NSString *)childProductId;

/** Returns BOOL indicating if the product is activated.
 *
 * @return A BOOL indicating if the product is activated.
 */
- (BOOL)productActivated;

/** Returns BOOL indicating if a product is activated.
 *
 * @param childProductId string containing the Paddle Product ID
 * @return A BOOL indicating if the request product is activated.
 */
- (BOOL)childProductActivated:(nonnull NSString *)childProductId;

/** Displays the Licensing/Activation Window. If the product is activated this will display the activated licence code.
 */
- (void)showLicencing;

/** Returns NSString for the activated licence code.
 *
 * @return An NSString of the currenyly activated licence code. If product is not activated, nil will be returned.
 */
- (nullable NSString *)activatedLicenceCode;

/** Returns NSString for the email used in the current activation.
 *
 * @return An NSString of the email used in the current activation. If product is not activated, nil will be returned.
 */
- (nullable NSString *)activatedEmail;

/** Displays the ActivateView for your product. One of the startLicensing methods must have been called before this
 */
- (void)showActivateLicence;

/** Displays the ActivateView for your product. One of the startLicensing methods must have been called before this
 *
 * @param window An NSWindow the purchase window should be attached as a sheet to if required. Can be nil for this to presented modally.
 */
- (void)showActivateLicenceWithWindow:(nullable NSWindow *)window;
/** Displays the ActivateView for a product. One of the startLicensing methods must have been called before this
 *
 * @param window An NSWindow the purchase window should be attached as a sheet to if required. Can be nil for this to presented modally.
 * @param childProductId A string containing the Paddle Product ID.
 */
- (void)showActivateLicenceWithWindow:(nullable NSWindow *)window forChildProduct:(nonnull NSString *)childProductId;

/** Displays the ActivateView for your product. One of the startLicensing methods must have been called before this
 *
 * @param window An NSWindow the purchase window should be attached as a sheet to if required. Can be nil for this to presented modally.
 * @param licenceCode an NSString to pre-fill the licence code with.
 * @param email an NSString to pre-fill the email with.
 * @param completionBlock A block to be called when an activation has completed, returning activation BOOL to indicate if the activation was successful.
 */
- (void)showActivateLicenceWithWindow:(nullable NSWindow *)window licenceCode:(nullable NSString *)licenceCode email:(nullable NSString *)email withCompletionBlock:(nonnull void(^)(BOOL activated))completionBlock;

/** Displays the ActivateView for a product.
 *
 * @param window An NSWindow the purchase window should be attached as a sheet to if required. Can be nil for this to presented modally.
 * @param licenceCode an NSString to pre-fill the licence code with.
 * @param email an NSString to pre-fill the email with.
 * @param childProductId A string containing the Paddle Product ID.
 * @param completionBlock A block to be called when an activation has completed, returning activation BOOL to indicate if the activation was successful.
 */
- (void)showActivateLicenceWithWindow:(nullable NSWindow *)window licenceCode:(nullable NSString *)licenceCode email:(nullable NSString *)email forChildProduct:(nonnull NSString *)childProductId withCompletionBlock:(nonnull void(^)(BOOL activated))completionBlock;

/** Activate a licence for your product without display any Paddle UI. One of the startLicensing methods must have been called before this
 *
 * @param licenceCode an NSString for the licence to activate.
 * @param email an NSString for the email to be used with activation..
 * @param completionBlock A block to be called when an activation has completed, returning activated BOOL to indicate if the activation was successful and an NSError error if it was unsuccessful.
 */
- (void)activateLicence:(nonnull NSString *)licenceCode email:(nonnull NSString *)email withCompletionBlock:(nonnull void (^)(BOOL activated, NSError * _Nullable error))completionBlock;

/** Activate a licence for a product without display any Paddle UI. One of the startLicensing methods must have been called before this
 *
 * @param licenceCode an NSString for the licence to activate.
 * @param email an NSString for the email to be used with activation.
 * @param childProductId A string containing the Paddle Product ID.
 * @param completionBlock A block to be called when an activation has completed, returning activated BOOL to indicate if the activation was successful and an NSError error if it was unsuccessful.
 */
- (void)activateLicence:(nonnull NSString *)licenceCode email:(nonnull NSString *)email forChildProduct:(nonnull NSString *)childProductId withCompletionBlock:(nonnull void (^)(BOOL activated, NSError * _Nullable error))completionBlock;

/** Remotely verify the existing activation in an effort to detect cracked licences.
 *
 * @param completionBlock A block to be called when an a remote verification has been performed. Returning a BOOL verified if the verification was successful and an NSError if it was not.
 */
- (void)verifyLicenceWithCompletionBlock:(nonnull void (^)(BOOL verified, NSError * _Nullable error))completionBlock;

/** Remotely verify an existing activation for a product in an effort to detect cracked licences.
 *
 * @param childProductId A string containing the Paddle Product ID.
 * @param completionBlock A block to be called when an a remote verification has been performed. Returning a BOOL verified if the verification was successful and an NSError if it was not.
 */
- (void)verifyLicenceForChildProduct:(nonnull NSString *)childProductId withCompletionBlock:(nonnull void (^)(BOOL verified, NSError * _Nullable error))completionBlock;

/** Deactivate the current licence. A delegate method will be called if implemented on success/fail
 */
- (void)deactivateLicence;

/** Deactivate the current licence. A delegate method will be called if implemented on success/fail
 *
 * @param childProductId A string containing the Paddle Product ID.
 */
- (void)deactivateLicenceForChildProduct:(nonnull NSString *)childProductId;

/** Deactivate the current licence.
 *
 * @param completionBlock A block to be called when a deactivateLicence call has been made, returning a BOOL deactivated to indicate if the deactivation was successful.
 */
- (void)deactivateLicenceWithCompletionBlock:(nonnull void (^)(BOOL deactivated, NSString * _Nullable deactivateMessage))completionBlock;

/** Recover a lost licence
 *
 * @param email an NSString containing the original email address used for purchasing the licence (licence codes will be sent to this address)
 * @param productId an NSString containing the product id of the licence that should be recovered
 * @param completionBlock a block to to be called when a response from the recoverLicence API has been received, returning a BOOL status to indicate if the recovery was successful
 */
- (void)recoverLicencesForEmail:(nullable NSString *)email productId:(nullable NSString *)productId withCompletionBlock:(nullable void (^)(BOOL status, NSString * _Nonnull message))completionBlock;

/** Set the title of the ProductView to a NSString other than the default response fromt the API.
 *
 * @param productHeading An NSString containing the title you would like to be displayed. Can be a Localizable string.
 */
- (void)setCustomProductHeading:(nonnull NSString *)productHeading;

/** Set the trial text of the ProductView to a NSString other than the default response fromt the API.
 *
 * @param productTrialText An NSString containing the trial text you would like to be displayed. Can be a Localizable string.
 */
- (void)setCustomProductTrialText:(nonnull NSString *)productTrialText;

/** Disable Trials completely. To be used when both Time Trials and Feature Trials are not needed.
 *
 * @param trialSetting A BOOL value, when set to YES disables trials.
 */
- (void)disableTrial:(BOOL)trialSetting;

/** Disable Migration of old (pre v2 SDK) licences to newer versions.
 */
- (void)disableLicenseMigration;

/** Disable resetting of Time Trials when a licence is deactivated. By default trials are reset to the standard duration after deactivation.
 */
- (void)disableTrialResetOnDeactivate;

/** Reset Trials when the app is updated.
 *
 * @param onlyMajor A BOOL value, when set to YES only resets trials when the version is a major version change (e.g v1 to v2), otherwise all version upgrades will reset a trial.
 */
- (void)resetTrialOnVersionUpdateForMajorOnly:(BOOL)onlyMajor;

/** Override the current price of the product and display the PurchaseView. One of the startLicensing methods must be called before using this.
 *
 * @param price An NSString containing the desired price in USD.
 */
- (void)overridePrice:(nonnull NSString *)price;

/** Override the current price of the product and display the PurchaseView. One of the startLicensing methods must be called before using this.
 *
 * @param price An NSString containing the desired price in USD.
 * @param customMessage An NSString containing a custom message to be displayed for the overridden price.
 * @param productName An NSString containing a custom product name to be displayed for the overridden price.
 */
- (void)overridePrice:(nonnull NSString *)price withCustomMessage:(nullable NSString *)customMessage customProductName:(nullable NSString *)productName;

/** Override the current price of the product and display the PurchaseView. One of the startLicensing methods must be called before using this.
 *
 * @param price An NSString containing the desired price in USD.
 * @param window An NSWindow the purchase window should be attached as a sheet to if required. Can be nil for this to presented modally.
 * @param completionBlock A block to be called when a purchase has completed, returning the email address used along with the licence code.
 */
- (void)overridePrice:(nonnull NSString *)price withWindow:(nullable NSWindow *)window completionBlock:(nonnull void (^)(NSString * _Nullable email, NSString * _Nullable licenceCode, BOOL activate, NSDictionary * _Nullable checkoutData))completionBlock;

/** Override the current price of a child product and display the PurchaseView.
 *
 * @param price An NSString containing the desired price in USD.
 * @param window An NSWindow the purchase window should be attached as a sheet to if required. Can be nil for this to presented modally.
 * @param childProductId an NSString containing the child product id
 * @param completionBlock A block to be called when a purchase has completed, returning the email address used along with the licence code.
 */
- (void)overridePrice:(nonnull NSString *)price withWindow:(nullable NSWindow *)window forChildProduct:(nonnull NSString *)childProductId completionBlock:(nonnull void (^)(NSString * _Nullable email, NSString * _Nullable licenceCode, BOOL activate, NSDictionary * _Nullable checkoutData))completionBlock;

/** Override the current price of the product and display the PurchaseView. One of the startLicensing methods must be called before using this.
 *
 * @param price An NSString containing the desired price in USD.
 * @param window An NSWindow the purchase window should be attached as a sheet to if required. Can be nil for this to presented modally.
 * @param customMessage An NSString containing a custom message to be displayed for the overridden price.
 * @param productName An NSString containing a custom product name to be displayed for the overridden price.
 * @param completionBlock A block to be called when a purchase has completed, returning the email address used along with the licence code.
 */
- (void)overridePrice:(nonnull NSString *)price withWindow:(nullable NSWindow *)window customMessage:(nullable NSString *)customMessage customProductName:(nullable NSString *)productName completionBlock:(nonnull void (^)(NSString * _Nullable email, NSString * _Nullable licenceCode, BOOL activate, NSDictionary * _Nullable checkoutData))completionBlock;

/** Override the current price of the product and open a purchase page in the users default browser.
 *
 * @param price An NSString containing the desired price in USD.
 */
- (void)overridePriceExternal:(nonnull NSString *)price;

/** Returns a dictionary containing licence details from another app contained in a shared app group.
 *
 * @param appGroup an NSString containing the ID of an app group that both the current app and other Paddle app have access to.
 * @param productId An NSString containing Paddle product ID of the other app.
 *
 * @return An NSDictionary containing licence details from other app.
 */
- (nullable NSDictionary *)existingLicenseFromAppGroup:(nonnull NSString *)appGroup forProductId:(nonnull NSString *)productId;

/** Set a Passthrough value to be sent to the Paddle API, which is included in webhooks to your own server. Can be used to track existing users against new purchases for example.
 *
 * @param passthrough An NSString containing the desired passthrough value. This will be URL Encoded.
 */
- (void)setPassthrough:(nonnull NSString *)passthrough;

/** Add a coupon for a particular productId. The PurchaseView will look for this coupon when start a purchase for that product ID.
 *
 * @param couponCode An NSString containing the coupon to be used.
 */
- (void)addCoupon:(nonnull NSString *)couponCode forProductId:(nullable NSString *)productId;

/** Add multiple coupons for different product IDs. The PurchaseView will look for these coupon when starting a purchase.
 *
 * @param coupons An NSArray containing the coupons to be used. Each object should be an NSDictionary containing a couponCode and a productId key/value
 */
- (void)addCoupons:(nonnull NSArray *)coupons;

/** Set any custom attributes to be used in the PurchaseView.
 *
 * @param checkoutAttributes An NSDictionary containing a list of custom attributes. A list can be found at: https://paddle.com/docs/paddlejs-buttons-checkout
 */
- (void)setCustomCheckoutAttributes:(nonnull NSDictionary<NSString *, id> *)checkoutAttributes;

- (void)forceLoadLicense;


@end
