pub mod license;
pub mod s3;

rustler::init!(
  "Elixir.TuistCloud.Native",
  [
      license::license,
      s3::s3_download_presigned_url,
      s3::s3_exists,
      s3::s3_multipart_start,
      s3::s3_multipart_generate_url,
      s3::s3_multipart_complete_upload,
      s3::s3_size,
      s3::s3_delete_all_objects,
  ]
);
