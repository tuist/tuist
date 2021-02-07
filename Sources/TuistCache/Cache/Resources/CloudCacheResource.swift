import TuistCore
import TuistSupport

typealias CloudExistsResource = HTTPResource<CloudResponse<CloudHEADResponse>, CloudHEADResponseError>

typealias CloudCacheResource = HTTPResource<CloudResponse<CloudCacheResponse>, CloudResponseError>

typealias CloudVerifyUploadResource = HTTPResource<CloudResponse<CloudVerifyUploadResponse>, CloudResponseError>
