use rustler;

use base64::decode;
use obfstr::obfstr as s;
use openssl::{
    encrypt::Decrypter,
    hash::MessageDigest,
    pkey::PKey,
    rsa::{Padding, Rsa},
    sign::Verifier,
};
use rustler::{NifStruct, NifTaggedEnum};
use serde::{Deserialize, Serialize};
use std::env;
use std::str;

#[derive(Debug, NifStruct, Serialize, Deserialize)]
#[module = "Tuist.Native.License"]
struct License {
    id: String,
    expiration_date: String,
    features: Vec<String>,
}

#[derive(NifTaggedEnum)]
enum LicenseResult {
    Error(String),
    Ok(License),
}

/// This function reads the environment variable `TUIST_LICENSE` and verifies the signature of the license.
/// This logic is implemented in Rust to be able to obfuscate the keys and the logic.
#[rustler::nif(schedule = "DirtyCpu")]
fn license() -> LicenseResult {
    // Keys
    let public_key_base_64: String = s!("LS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0tLS0KTUlJQklqQU5CZ2txaGtpRzl3MEJBUUVGQUFPQ0FROEFNSUlCQ2dLQ0FRRUFxWTFBUHJzRTVCR042SnJmT1RQTQpIRlZraHhRbWIwRG5QSU8xdEY3MW1oTWJTWUZWUXc0NDZIQS9YUXFBUVZMQ2k2YklJSXlZME1QVTQyMGJremJWCkpoNHRyaUdUamxweHNaWHhSdnJNQXlQb3JoeHZyaGJoUVNMdmx1YmNPRlh4TldlQm5NRVNZczM1bkFlSy93L3AKZkIxT05oYU9uZmZVbWVMUHdqMkhneElFd0VrbDFrWXp1VDRxRE1ER0dSZHZZL3pFR3NGSmc2REgwQlJKUVBnRQpJcGcwckJpN05WUTlQdWxqZ3VXTllQVk5SZWw0N2RuR0hQSW1sQmM2a3Y3ZFEvbUFaUThPSkNaalRrem5vbmVmCnFRV1RyS2psWmoxcEJKbVdGYlo3R1RaRmhyRURmYlZKeXRHTGVGb1huSmRNM0JjMFdlZ3l1dTlmcGQyeDFuWmoKandJREFRQUIKLS0tLS1FTkQgUFVCTElDIEtFWS0tLS0tCg==").to_string();
    let private_key_base_64: String = s!("LS0tLS1CRUdJTiBQUklWQVRFIEtFWS0tLS0tCk1JSUV2UUlCQURBTkJna3Foa2lHOXcwQkFRRUZBQVNDQktjd2dnU2pBZ0VBQW9JQkFRQ3BqVUErdXdUa0VZM28KbXQ4NU04d2NWV1NIRkNadlFPYzhnN1cwWHZXYUV4dEpnVlZERGpqb2NEOWRDb0JCVXNLTHBzZ2dqSmpRdzlUagpiUnVUTnRVbUhpMnVJWk9PV25HeGxmRkcrc3dESStpdUhHK3VGdUZCSXUrVzV0dzRWZkUxWjRHY3dSSml6Zm1jCkI0ci9EK2w4SFU0MkZvNmQ5OVNaNHMvQ1BZZURFZ1RBU1NYV1JqTzVQaW9Nd01ZWkYyOWovTVFhd1VtRG9NZlEKRkVsQStBUWltRFNzR0xzMVZEMCs2V09DNVkxZzlVMUY2WGp0MmNZYzhpYVVGenFTL3QxRCtZQmxEdzRrSm1OTwpUT2VpZDUrcEJaT3NxT1ZtUFdrRW1aWVZ0bnNaTmtXR3NRTjl0VW5LMFl0NFdoZWNsMHpjRnpSWjZESzY3MStsCjNiSFdkbU9QQWdNQkFBRUNnZ0VBR1BzdTFBOUtFVEJrOERpaFd4UStwbzRPV2JpbVVRNEhBK3VFQWlkYm1HL28KUFZSSTg3Qk13aktIbzNYQW45OUp1cm5BRXN1a1dGNENKK0FUaUFVME1vR1B5WEE1QldoZUNBUkhvR1dqV1hNWQovVTVEUmlzbzFTZ0lsUHMreHk0aWMvUGtMT3hsZ1JsSUJhMDIxWTNLb1BiUVp6ZTdtNXJBUUV3aXdFUEFpNWNHCkh2K0Y1MUY5c1RXZTdWQzJnNGRyOUxnUkgwUDRjTE1ha283alhQbTNqazA5ZHlXS1d5aGZWVHJkWFVIUXFvc1YKRDJEU3ZhT2dZeTBzTGhzc3dLRFpiYnhjU0JRSU5BZUxKcU0wVzE1aW40bGRMeldzeTg1SXJvTGRQeTVRV1hRSwpQVko2NW52OTVYUXBaTlV4c1FIUnE0VVdFam1iNXBQSnozeDBJK0Jrd1FLQmdRRHRyVW1ydE9oOVNDenNFdk0vCnU3UjNrWCtJa0VITHNwYUdVUGI1dkxNQWtvclhVUXIwbGZ5QXNuclI3SWZLczlyMDJZOVB5QllhbGlrMXYyTmYKbW1xYWtBTHAyTFk4Q2pwbGR3aWY0MDJReWdxY3hJWklkK3V5TC9yQVpVdzFJd2x4K3ljUFpiVHo5Rkd6Y3BRWApJb3laUk5TSUJzd2F0N3J4WUtiZXZSUnJOUUtCZ1FDMm4zZlJWU0l4WXNUaVJiNG5CV3ZqeG9GUjFDd2xQNmtICmNiYTJFWnBlVnQ4SElOd2JCS2Ira3ZMWkQzNnd2cHVGdnlBenl3Zk9JVUZ0cXlZWmNFUFNWRjNUVFZpWjVPZVAKTE1qNUdNN285ZjQ3bkZkUm1QbVRTSXNDbVdvUzJrWXVFdkZ6VTJyblRDaDlwS3U5dHRJQU9tVXozMUJSc3AzVgpETmUxbStub013S0JnUUN1ZTdqSnhWV29JNFJYQ3RKb3gzUUZFMXQ4OWVwWGtCUFJKejhvdDg3eGJLTmd6cTRzClFLL09DemovUTVXc3liekVZN05CN3JITGN0RnVFOEx3UEh4bVc3TEgyY0J1ODFOTGljZGJHWk9uNTZ0Q3kwT0oKa0FBSUlCRUZqVmdVNmxQVXlYd3pZWWNtVVFacHBvUHhOL3ZmeVJmOWhIL3lYVTl3UkhROHNMSjh3UUtCZ0d6YwoxTlVCZGRlUXRDTGFSa2NHa1ZEL2RQbHRqRDlNR3B1b2FxMVFBd0Izc28yU1JnTUpHKzhuZEFKMm5TUUpDN2FICnYwK0FtUStFZlhjOWpnR2VEWi9rME9Wejl2d09Hd2NiUUZaVk5vcGlrWUhCYWIvbmUrY1RXR0pkUjRFamdyQlcKZEg0MTNNVXlmZlNmNUF5OFhhVHJLb2JvZVAycWh6R0liVklDTmtaSEFvR0FRZ2YyZ3IxMjE1OGFFemI3d3phWQpxZGZnd0xub3RzT1dtaFVYRjVGa1I5RHF6UHRXeFdDNENGWWkvTkFjSzZSTyt5VndPOHZjZjlIazJ0SFlIWHBYCnFDeHdIczdpWVNzZXpZR3Y1Y040U0dDS2xySjllYXh3OUpZd05aYXZXMFhwRjZKVXVLU0hqbTU3OGp3WFJNWmIKYzhoTUc3TFBwVm5HbXozdEFMTGhvbnM9Ci0tLS0tRU5EIFBSSVZBVEUgS0VZLS0tLS0K").to_string();
    let public_key_string = String::from_utf8(decode(&public_key_base_64).unwrap()).unwrap();
    let private_key_string = String::from_utf8(decode(&private_key_base_64).unwrap()).unwrap();
    let public_key = Rsa::public_key_from_pem(public_key_string.as_bytes()).unwrap();
    let private_key = Rsa::private_key_from_pem(private_key_string.as_bytes()).unwrap();
    let public_pkey = PKey::from_rsa(public_key).unwrap();
    let private_pkey = PKey::from_rsa(private_key).unwrap();

    // License environment variable
    let tuist_license = match env::var("TUIST_LICENSE") {
        Ok(val) => val,
        Err(_) => {
            return LicenseResult::Error(
                "The license environment variable TUIST_LICENSE is missing".to_string(),
            )
        }
    };

    let parts: Vec<&str> = tuist_license.split('.').collect();
    if parts.len() != 2 {
        return LicenseResult::Error("The license is not in the expected format".to_string());
    }

    let (encrypted_base64, signature_base64) = (parts[0], parts[1]);
    let encrypted_data = match decode(encrypted_base64) {
        Ok(data) => data,
        Err(_) => {
            return LicenseResult::Error(
                "The encrypted data of the license is not a valid base64 string".to_string(),
            )
        }
    };

    let signature = match decode(signature_base64) {
        Ok(data) => data,
        Err(_) => {
            return LicenseResult::Error(
                "The signature of the license is not a valid base64 string".to_string(),
            )
        }
    };

    // Verify the signature
    let mut verifier = Verifier::new(MessageDigest::sha256(), &public_pkey).unwrap();
    verifier.update(&encrypted_base64.as_bytes()).unwrap();
    if !verifier.verify(&signature).unwrap() {
        return LicenseResult::Error("The signature of the license is invalid".to_string());
    }

    // Decrypt the data
    let mut decrypter = Decrypter::new(&private_pkey).unwrap();
    decrypter.set_rsa_padding(Padding::PKCS1).unwrap();
    let mut decrypted_data = vec![0; private_pkey.size() as usize];
    let decrypted_len = match decrypter.decrypt(&encrypted_data, &mut decrypted_data) {
        Ok(len) => len,
        Err(_) => {
            return LicenseResult::Error("The encrypted data of the license is invalid".to_string())
        }
    };

    decrypted_data.truncate(decrypted_len);

    let result = str::from_utf8(&decrypted_data)
        .map(|s| s.to_string())
        .unwrap();

    let license_metadata: License = match serde_json::from_str(&result) {
        Ok(license) => license,
        Err(err) => {
            return LicenseResult::Error(format!("Error deserializing the license: {}", err))
        }
    };

    return LicenseResult::Ok(license_metadata);
}
