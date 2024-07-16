use awscreds::Credentials;
use rustler;
use rustler::{NifStruct, NifTaggedEnum, NifTuple};
use s3::serde_types::Part;
use s3::Bucket;
use s3::Region;
use serde::{Deserialize, Serialize};
use std::str;
use std::time::Duration;
use std::collections::HashMap;
#[derive(NifStruct, Debug, Serialize, Deserialize)]
#[module = "Tuist.Native.S3AccessKeyPair"]
struct AccessKeyPair {
    access_key: String,
    secret_key: String,
}

#[derive(NifTaggedEnum, Debug, Serialize, Deserialize)]
enum S3Credentials {
    AccessKey(AccessKeyPair),
    Environment,
}

#[derive(NifTaggedEnum, Debug, Serialize, Deserialize)]
enum S3DownloadPresignedURLResult {
    Error(String),
    Ok(String),
}

#[derive(NifTuple, Debug, Serialize, Deserialize)]
struct EnvironmentVariable {
    key: String,
    value: String,
}

#[derive(NifStruct, Debug, Serialize, Deserialize)]
#[module = "Tuist.Native.S3DownloadPresignedURLOptions"]
struct S3DownloadPresignedURLOptions {
    expires_in: u32,
    credentials: S3Credentials,
    object_key: String,
    region: S3Region,
    bucket_name: String,
}


#[derive(NifTaggedEnum, Debug, Serialize, Deserialize)]
enum S3Region {
    Auto,
    Fixed { region: String, endpoint: String },
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn s3_download_presigned_url(
    options: S3DownloadPresignedURLOptions,
) -> S3DownloadPresignedURLResult {
    let bucket = match bucket(options.bucket_name, options.credentials, options.region) {
        Ok(bucket) => bucket,
        Err(err) => return S3DownloadPresignedURLResult::Error(err),
    };

    let url = match bucket.presign_get_blocking(&options.object_key, options.expires_in, None) {
        Ok(url) => url,
        Err(err) => return S3DownloadPresignedURLResult::Error(err.to_string()),
    };
    S3DownloadPresignedURLResult::Ok(url)
}

#[derive(NifTaggedEnum, Debug, Serialize, Deserialize)]
enum S3ExistsResult {
    Error(String),
    Ok(bool),
}

#[derive(NifStruct, Debug, Serialize, Deserialize)]
#[module = "Tuist.Native.S3ExistsOptions"]
struct S3ExistsOptions {
    credentials: S3Credentials,
    object_key: String,
    region: S3Region,
    bucket_name: String,
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn s3_exists(options: S3ExistsOptions) -> S3ExistsResult {
    let bucket = match bucket(options.bucket_name, options.credentials, options.region) {
        Ok(bucket) => bucket,
        Err(err) => return S3ExistsResult::Error(err),
    };

    S3ExistsResult::Ok(bucket.head_object_blocking(options.object_key).is_ok())
}

#[derive(NifTaggedEnum, Debug, Serialize, Deserialize)]
enum S3GetObjectResult {
    Error(String),
    Ok(String),
}

#[derive(NifStruct, Debug, Serialize, Deserialize)]
#[module = "Tuist.Native.S3GetObjectOptions"]
struct S3GetObjectOptions {
    credentials: S3Credentials,
    object_key: String,
    region: S3Region,
    bucket_name: String,
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn s3_get_object_as_string(options: S3GetObjectOptions) -> S3GetObjectResult {
    let bucket = match bucket(options.bucket_name, options.credentials, options.region) {
        Ok(bucket) => bucket,
        Err(err) => return S3GetObjectResult::Error(err),
    };

    let object = match bucket.get_object_blocking(options.object_key) {
        Ok(object) => object,
        Err(err) => return S3GetObjectResult::Error(err.to_string()),
    };

    match object.to_string() {
        Ok(object_string) => return S3GetObjectResult::Ok(object_string),
        Err(err) => return S3GetObjectResult::Error(err.to_string()),
    };
}

#[derive(NifTaggedEnum, Debug, Serialize, Deserialize)]
enum S3MultipartStartResult {
    Error(String),
    Ok(String),
}

#[derive(NifStruct, Debug, Serialize, Deserialize)]
#[module = "Tuist.Native.S3MultipartStartOptions"]
struct S3MultipartStartOptions {
    credentials: S3Credentials,
    object_key: String,
    region: S3Region,
    bucket_name: String,
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn s3_multipart_start(options: S3MultipartStartOptions) -> S3MultipartStartResult {
    let bucket = match bucket(options.bucket_name, options.credentials, options.region) {
        Ok(bucket) => bucket,
        Err(err) => return S3MultipartStartResult::Error(err),
    };

    match bucket.initiate_multipart_upload_blocking(&options.object_key, "application/octet-stream")
    {
        Ok(upload) => S3MultipartStartResult::Ok(upload.upload_id),
        Err(err) => return S3MultipartStartResult::Error(err.to_string()),
    }
}

#[derive(NifStruct, Debug, Serialize, Deserialize)]
#[module = "Tuist.Native.S3MultipartGenerateURLOptions"]
struct S3MultipartGenerateURLOptions {
    expires_in: u32,
    credentials: S3Credentials,
    object_key: String,
    bucket_name: String,
    part_number: u32,
    upload_id: String,
    region: S3Region,
}

#[derive(NifTaggedEnum, Debug, Serialize, Deserialize)]
enum S3MultipartGenerateURLResult {
    Error(String),
    Ok(String),
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn s3_multipart_generate_url(
    options: S3MultipartGenerateURLOptions,
) -> S3MultipartGenerateURLResult {
    let bucket = match bucket(options.bucket_name, options.credentials, options.region) {
        Ok(bucket) => bucket,
        Err(err) => return S3MultipartGenerateURLResult::Error(err),
    };
    let url = match bucket.presign_put_blocking(
        &options.object_key,
        options.expires_in,
        None,
        Some(HashMap::from([
            ("partNumber".to_string(), options.part_number.to_string()),
            ("uploadId".to_string(), options.upload_id.clone()),
        ])),
    ) {
        Ok(url) => url,
        Err(err) => return S3MultipartGenerateURLResult::Error(err.to_string()),
    };
    S3MultipartGenerateURLResult::Ok(url)
}

#[derive(NifStruct, Debug, Serialize, Deserialize)]
#[module = "Tuist.Native.S3SizeOptions"]
struct S3SizeOptions {
    credentials: S3Credentials,
    object_key: String,
    bucket_name: String,
    region: S3Region,
}

#[derive(NifTaggedEnum, Debug, Serialize, Deserialize)]
enum S3SizeResult {
    Error(String),
    Ok(i64),
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn s3_size(options: S3SizeOptions) -> S3SizeResult {
    let bucket = match bucket(options.bucket_name, options.credentials, options.region) {
        Ok(bucket) => bucket,
        Err(err) => return S3SizeResult::Error(err),
    };

    let size = match bucket.head_object_blocking(&options.object_key) {
        Ok((object, _)) => object.content_length,
        Err(err) => return S3SizeResult::Error(err.to_string()),
    };
    match size {
        None => return S3SizeResult::Error("Object not found".to_string()),
        Some(size) => S3SizeResult::Ok(size),
    }
}

#[derive(NifStruct, Debug, Serialize, Deserialize)]
#[module = "Tuist.Native.S3MultipartCompleteUploadOptions"]
struct S3MultipartCompleteUploadOptions {
    credentials: S3Credentials,
    object_key: String,
    bucket_name: String,
    upload_id: String,
    region: S3Region,
    parts: Vec<S3MultipartCompleteUploadOptionsPart>,
}

#[derive(NifTuple, Debug, Serialize, Deserialize)]
struct S3MultipartCompleteUploadOptionsPart {
    part_number: u32,
    etag: String,
}

#[derive(NifTaggedEnum, Debug, Serialize, Deserialize)]
enum S3MultipartCompleteUploadResult {
    Error(String),
    Ok,
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn s3_multipart_complete_upload(
    options: S3MultipartCompleteUploadOptions,
) -> S3MultipartCompleteUploadResult {
    let bucket = match bucket(options.bucket_name, options.credentials, options.region) {
        Ok(bucket) => bucket,
        Err(err) => return S3MultipartCompleteUploadResult::Error(err),
    };

    let mut parts: Vec<Part> = Vec::new();
    for part in &options.parts {
        parts.push(Part {
            part_number: part.part_number,
            etag: part.etag.clone(),
        });
    }

    match bucket.complete_multipart_upload_blocking(&options.object_key, &options.upload_id, parts)
    {
        Ok(_) => S3MultipartCompleteUploadResult::Ok,
        Err(err) => S3MultipartCompleteUploadResult::Error(err.to_string()),
    }
}

#[derive(NifStruct, Debug, Serialize, Deserialize)]
#[module = "Tuist.Native.S3DeleteAllObjectsOptions"]
struct S3DeleteAllObjectsOptions {
    credentials: S3Credentials,
    prefix: String,
    bucket_name: String,
    region: S3Region,
}

#[derive(NifTaggedEnum, Debug, Serialize, Deserialize)]
enum S3DeleteAllObjectsResult {
    Error(String),
    Ok,
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn s3_delete_all_objects(options: S3DeleteAllObjectsOptions) -> S3DeleteAllObjectsResult {
    let bucket = match bucket(options.bucket_name, options.credentials, options.region) {
        Ok(bucket) => bucket,
        Err(err) => return S3DeleteAllObjectsResult::Error(err),
    };

    match bucket.list_blocking(options.prefix, Some("/".to_string())) {
        Ok(objects) => {
            for object in objects {
                for obj in object.contents {
                    _ = bucket.delete_object_blocking(&obj.key)
                }
            }
        }
        Err(_) => (),
    }
    S3DeleteAllObjectsResult::Ok
}

fn bucket(name: String, credentials: S3Credentials, region: S3Region) -> Result<Bucket, String> {
    let credentials = match credentials {
        S3Credentials::AccessKey(access_key_pair) => Credentials {
            access_key: Some(access_key_pair.access_key),
            secret_key: Some(access_key_pair.secret_key),
            security_token: None,
            session_token: None,
            expiration: None,
        },
        S3Credentials::Environment => match Credentials::default() {
            Ok(credentials) => credentials,
            Err(err) => return Err(err.to_string()),
        },
    };
    let s3_region: Region = match region {
        S3Region::Fixed {region, endpoint} => Region::Custom {
            region: region,
            endpoint: endpoint,
        },
        S3Region::Auto => match Region::from_default_env() {
            Ok(region) => region,
            Err(err) => return Err(err.to_string()),
        }
    };
    let bucket = match Bucket::new(&name, s3_region, credentials).and_then(|bucket| bucket.with_request_timeout(Duration::from_secs(90))) {
        Ok(bucket) => bucket,
        Err(err) => return Err(err.to_string()),
    };
    return Ok(bucket);
}
