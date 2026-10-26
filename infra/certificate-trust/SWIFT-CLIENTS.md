# Swift native transport qualification

## Local production gRPC and HTTPS CONNECT

`CertificateTrustGRPCTests` uses the actual `REAPITransport.make` factory and
`GetCapabilities` service over HTTP/2, not only an isolated TLS handler. The
server requires h2 ALPN. Synthetic OpenSSL 3 certificates form separate
root/intermediate/leaf chains for the origin and HTTPS proxy. Neither server
sends its root; roots are provided through `TUIST_CA_CERTIFICATE` alongside
ordinary system trust.

The default-empty internal `additionalBlockedSPKIHashes` argument only adds
restrictions to the embedded twelve-key policy. It reaches both TLS handlers.
Accepted connections precede the leaf/intermediate/absent-root differentials,
and another accepted connection follows the failures. Denied proxy keys leave
CONNECT headers undelivered; denied origin keys leave authenticated service
metadata undelivered. Assertions check Basic proxy authentication only at
CONNECT, Bearer/account metadata only at the service, and no proxy authorization
at the origin. Delivery evidence is handler counts plus verified TLS write
ordering, not a packet capture. Every RPC creates a new transport.

The fixture uses Swift Testing temporary directories and task-scoped mocked
environments, requires default HTTP settings, and owns its servers, channels and
event loops. It does not mutate host trust or global proxy variables. Generated
fixture keys are unrelated to the incident and are never publication inputs.

On macOS 27 with Xcode 27.2, six tests in the two certificate suites passed,
including the explicit credential-free public opt-in. The real incident DER
suite proves twelve-key hashing; synthetic chains prove application wiring.
Public controls can fail natively and do not prove callback execution.

```sh
DEVELOPER_DIR=/Applications/Xcode-27.2.app/Contents/Developer \
  tuist generate TuistREAPI TuistREAPITests --no-open
TEST_RUNNER_TUIST_TRUST_LIVE=1 \
DEVELOPER_DIR=/Applications/Xcode-27.2.app/Contents/Developer \
  xcodebuild test -workspace Tuist.xcworkspace -scheme Tuist-Workspace \
  -destination 'platform=macOS' \
  -only-testing:TuistREAPITests/CertificateTrustTests \
  -only-testing:TuistREAPITests/CertificateTrustGRPCTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
```

## Remaining boundaries

This qualifies local unary origin/proxy wiring on Apple's default-root native
path, not Linux FoundationNetworking, the non-Apple BoringSSL path, every stream
or transfer, NO_PROXY/plaintext-proxy integration, minimum OS versions, signed
releases or installed clients. Foundation/app and standalone SwifterPM retain
separate evidence and release gates. The matched-Xcode SwifterPM runner remains
qualification-only, not a default-command or portable CI repair.
