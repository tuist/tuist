package dev.tuist.atlas.trusttest;

import android.app.Activity;
import android.app.Instrumentation;
import android.net.http.X509TrustManagerExtensions;
import android.os.Bundle;
import java.io.InputStream;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.net.InetSocketAddress;
import java.net.URL;
import java.security.KeyStore;
import java.security.cert.Certificate;
import java.security.cert.CertificateException;
import java.security.cert.CertificateFactory;
import java.security.cert.CertPathValidatorException;
import java.security.cert.X509Certificate;
import java.util.Collections;
import java.util.List;
import java.util.Set;
import java.util.TreeSet;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import javax.net.ssl.HttpsURLConnection;
import javax.net.ssl.SSLContext;
import javax.net.ssl.SSLParameters;
import javax.net.ssl.SSLSocket;
import javax.net.ssl.SSLSocketFactory;
import javax.net.ssl.TrustManager;
import javax.net.ssl.TrustManagerFactory;
import javax.net.ssl.X509TrustManager;

/** Separate opt-in test APK. Loads the policy from the actual target APK, never a source copy. */
public final class CertificateTrustInstrumentation extends Instrumentation {
    @Override public void onCreate(Bundle arguments) {
        super.onCreate(arguments);
        start();
    }

    @Override public void onStart() {
        Bundle result = new Bundle();
        String stage = "policy DER";
        try {
            Class<?> type = Class.forName("dev.tuist.atlas.AtlasCertificateTrust", true, getTargetContext().getClassLoader());
            Object policy = type.getField("INSTANCE").get(null);
            Method open = type.getMethod("openConnection", URL.class);
            Method hash = type.getMethod("spkiHash", X509Certificate.class);
            Method factory = type.getMethod("socketFactory", X509TrustManager.class, Set.class);
            Method allowed = type.getMethod("requireAllowed", List.class, Set.class);
            Set<String> hashes = new TreeSet<>();
            for (String name : new String[]{"issuer-roots.pem", "distrusted-intermediates.pem"}) {
                try (InputStream input = getContext().getAssets().open(name)) {
                    for (Certificate certificate : CertificateFactory.getInstance("X.509").generateCertificates(input)) {
                        hashes.add((String) hash.invoke(policy, certificate));
                        try {
                            allowed.invoke(policy, Collections.singletonList(certificate), Collections.emptySet());
                            throw new AssertionError("real incident certificate key was not denied");
                        } catch (InvocationTargetException failure) {
                            require(keyDeny(failure.getCause()), "real DER failure was not application key denial");
                        }
                    }
                }
            }
            require(hashes.size() == 12, "expected twelve independent fixture keys");
            require(hashes.equals(type.getMethod("getBlockedSPKIHashes").invoke(policy)), "embedded policy differs from real DER");
            int positiveFixtures = 0;
            for (String name : new String[]{"positive-isrg-root-x1.pem", "positive-isrg-r11.pem"}) {
                try (InputStream input = getContext().getAssets().open(name)) {
                    for (Certificate certificate : CertificateFactory.getInstance("X.509").generateCertificates(input)) {
                        allowed.invoke(policy, Collections.singletonList(certificate), Collections.emptySet());
                        positiveFixtures++;
                    }
                }
            }
            require(positiveFixtures == 2, "missing independent healthy fixture keys");
            stage = "native reference chain";
            TrustManagerFactory managers = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());
            managers.init((KeyStore) null);
            X509TrustManager original = null;
            for (TrustManager manager : managers.getTrustManagers()) {
                if (manager instanceof X509TrustManager) original = (X509TrustManager) manager;
            }
            require(original != null, "native trust manager unavailable");
            URL positive = new URL("https://valid-isrgrootx1.letsencrypt.org/");
            HttpsURLConnection reference = (HttpsURLConnection) positive.openConnection();
            try {
                configure(reference);
                require(reference.getResponseCode() == 200, "native reference HTTPS did not succeed");
            } finally { reference.disconnect(); }
            // Inspect the TLS peer chain directly, not an HTTP library's potentially cleaned chain.
            SSLContext nativeContext = SSLContext.getInstance("TLS");
            nativeContext.init(null, new TrustManager[]{original}, null);
            List<X509Certificate> path;
            int suppliedCount;
            Set<String> suppliedKeys = new TreeSet<>();
            try (SSLSocket socket = (SSLSocket) nativeContext.getSocketFactory().createSocket()) {
                socket.connect(new InetSocketAddress(positive.getHost(), 443), 10000);
                socket.setSoTimeout(10000);
                SSLParameters parameters = socket.getSSLParameters();
                parameters.setEndpointIdentificationAlgorithm("HTTPS");
                socket.setSSLParameters(parameters);
                socket.startHandshake();
                Certificate[] supplied = socket.getSession().getPeerCertificates();
                suppliedCount = supplied.length;
                X509Certificate[] peer = new X509Certificate[supplied.length];
                for (int index = 0; index < supplied.length; index++) {
                    peer[index] = (X509Certificate) supplied[index];
                    suppliedKeys.add((String) hash.invoke(policy, peer[index]));
                }
                path = new X509TrustManagerExtensions(original).checkServerTrusted(peer, peer[0].getPublicKey().getAlgorithm(), positive.getHost());
            }
            stage = "native path: verified=" + path.size() + ", supplied=" + suppliedCount;
            require(path.size() >= 3, "native path did not include an intermediate and anchor");
            require(path.size() > suppliedCount, "native anchor was not constructed independently of the wire chain");
            require(!suppliedKeys.contains((String) hash.invoke(policy, path.get(path.size() - 1))), "anchor key was already supplied by the peer");
            stage = "protected healthy control";
            HttpsURLConnection accepted = (HttpsURLConnection) open.invoke(policy, positive);
            try {
                configure(accepted);
                require(!accepted.getInstanceFollowRedirects(), "native image transport must not follow unprotected redirects");
                require(accepted.getResponseCode() == 200, "protected positive HTTPS did not succeed");
            } finally { accepted.disconnect(); }
            stage = "constructed-path key denies";
            for (X509Certificate certificate : path) {
                String key = (String) hash.invoke(policy, certificate);
                SSLSocketFactory denied = (SSLSocketFactory) factory.invoke(policy, original, Collections.singleton(key));
                HttpsURLConnection connection = (HttpsURLConnection) open.invoke(policy, positive);
                connection.setSSLSocketFactory(denied);
                try {
                    configure(connection);
                    connection.getResponseCode();
                    throw new AssertionError("otherwise accepted key was not denied");
                } catch (java.io.IOException failure) {
                    require(certificateFailure(failure), "accepted-key failure was not certificate-specific");
                    require(keyDeny(failure), "accepted-key failure did not come from the application policy");
                } finally { connection.disconnect(); }
            }
            int ordinaryControl = 0;
            for (String address : new String[]{"https://wrong.host.badssl.com/", "https://expired.badssl.com/", "https://self-signed.badssl.com/"}) {
                stage = "ordinary certificate control " + ordinaryControl++;
                HttpsURLConnection connection = (HttpsURLConnection) open.invoke(policy, new URL(address));
                try {
                    configure(connection);
                    connection.getResponseCode();
                    throw new AssertionError("ordinary native certificate validation was bypassed");
                } catch (java.io.IOException failure) {
                    require(certificateFailure(failure) || failure instanceof javax.net.ssl.SSLPeerUnverifiedException,
                            "ordinary negative failed without a certificate or hostname cause");
                } finally { connection.disconnect(); }
            }
            stage = "restored healthy control";
            HttpsURLConnection restored = (HttpsURLConnection) open.invoke(policy, positive);
            try {
                configure(restored);
                require(restored.getResponseCode() == 200, "healthy control did not recover");
            } finally { restored.disconnect(); }
            stage = "public certificate controls";
            int controls = 0;
            for (String issuer : new String[]{"emudhra", "aaa-emudhra"}) {
                for (String prefix : new String[]{"dv-g3b", "dv-g3c", "ov-g3b", "ov-g3c", "ev-g3b", "ev-g3c"}) {
                    URL url = new URL("https://" + prefix + "-" + issuer + ".we-have-a-problem.com/");
                    HttpsURLConnection connection = (HttpsURLConnection) open.invoke(policy, url);
                    try {
                        configure(connection);
                        connection.getResponseCode();
                        throw new AssertionError("public incident control accepted");
                    } catch (java.io.IOException failure) {
                        require(certificateFailure(failure), "public control failed without a certificate-specific cause");
                        controls++;
                    } finally { connection.disconnect(); }
                }
            }
            stage = "production favicon loader";
            ClassLoader targetLoader = getTargetContext().getClassLoader();
            Class<?> logos = Class.forName("dev.tuist.atlas.AccountLogos", true, targetLoader);
            java.lang.reflect.Field instance = logos.getDeclaredField("INSTANCE");
            instance.setAccessible(true);
            Class<?> callbackType = Class.forName("kotlin.jvm.functions.Function1", true, targetLoader);
            Object unit = Class.forName("kotlin.Unit", true, targetLoader).getField("INSTANCE").get(null);
            CountDownLatch loaded = new CountDownLatch(1);
            AtomicReference<android.graphics.Bitmap> image = new AtomicReference<>();
            Object completion = Proxy.newProxyInstance(targetLoader, new Class<?>[]{callbackType}, (proxy, method, arguments) -> {
                if (method.getName().equals("invoke")) {
                    image.set((android.graphics.Bitmap) arguments[0]);
                    loaded.countDown();
                }
                return unit;
            });
            Method load = logos.getDeclaredMethod("load", String.class, callbackType);
            load.setAccessible(true);
            Object cancel = load.invoke(instance.get(null), "tuist.dev", completion);
            try {
                require(loaded.await(30, TimeUnit.SECONDS), "production favicon timed out");
                require(image.get() != null && image.get().getWidth() > 0 && image.get().getWidth() <= 128,
                        "production favicon did not decode a bounded healthy image");
            } finally {
                Class.forName("kotlin.jvm.functions.Function0", true, targetLoader).getMethod("invoke").invoke(cancel);
            }
            result.putString("stream", "PASS: actual Atlas APK/native NSC; real twelve-key DER; accepted constructed-path keys denied; twelve public controls rejected; unrelated HTTPS 200; production favicon decoded; manager=" + original.getClass().getName() + "; controls=" + controls + "; path_keys=" + path.size() + "; wire_keys=" + suppliedCount + "\n");
            finish(Activity.RESULT_OK, result);
        } catch (Throwable failure) {
            // Deliberately exclude exception text, URLs, request headers and response bodies.
            result.putString("stream", "FAIL: Atlas certificate control at " + stage + " (" + failure.getClass().getSimpleName() + ")\n");
            finish(Activity.RESULT_CANCELED, result);
        }
    }

    private static void configure(HttpsURLConnection connection) {
        connection.setConnectTimeout(10000);
        connection.setReadTimeout(10000);
        connection.setRequestProperty("Connection", "close");
        connection.setUseCaches(false);
    }

    private static boolean certificateFailure(Throwable error) {
        for (int depth = 0; error != null && depth < 32; depth++, error = error.getCause()) {
            if (error instanceof CertificateException || error instanceof CertPathValidatorException) return true;
        }
        return false;
    }

    private static boolean keyDeny(Throwable error) {
        for (int depth = 0; error != null && depth < 32; depth++, error = error.getCause()) {
            if (error.getMessage() != null && error.getMessage().contains("distrusted public key")) return true;
        }
        return false;
    }

    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
}
