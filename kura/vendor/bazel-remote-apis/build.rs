fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("cargo:rerun-if-changed=build.rs");
    #[cfg(feature = "codegen")]
    {
        let out_dir = std::path::Path::new("src/generated");
        let protos = &[
            "vendor/github.com/bazelbuild/remote-apis/build/bazel/remote/execution/v2/remote_execution.proto",
            "vendor/github.com/bazelbuild/remote-apis/build/bazel/remote/asset/v1/remote_asset.proto",
            "vendor/github.com/bazelbuild/remote-apis/build/bazel/remote/logstream/v1/remote_logstream.proto",
            "vendor/github.com/googleapis/googleapis/google/bytestream/bytestream.proto",
        ];

        let includes = &[
            "vendor/github.com/bazelbuild/remote-apis/",
            "vendor/github.com/googleapis/googleapis",
        ];

        for proto_file in protos {
            println!("cargo:rerun-if-changed={}", proto_file);
        }

        let descriptor_path = out_dir.join("proto_descriptor.bin");
        tonic_prost_build::configure()
            .out_dir(out_dir)
            .file_descriptor_set_path(&descriptor_path)
            .compile_well_known_types(true)
            .compile_protos(protos, includes)?;

        let descriptor_set = std::fs::read(descriptor_path)?;
        pbjson_build::Builder::new()
            .register_descriptors(&descriptor_set)?
            .out_dir(out_dir)
            .build(&["."])?;
    }
    Ok(())
}
