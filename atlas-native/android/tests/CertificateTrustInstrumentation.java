package dev.tuist.atlas.trusttest;

import android.app.Activity;
import android.app.Instrumentation;
import android.net.http.X509TrustManagerExtensions;
import android.os.Bundle;
import java.lang.reflect.Method;
import java.net.URL;
import java.security.KeyStore;
import java.security.cert.Certificate;
import java.security.cert.CertificateException;
import java.security.cert.CertPathValidatorException;
import java.security.cert.X509Certificate;
import java.util.Collections;
import java.util.List;
import java.util.Set;
import javax.net.ssl.HttpsURLConnection;
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
        try {
            Class<?> type = Class.forName("dev.tuist.atlas.AtlasCertificateTrust", true, getTargetContext().getClassLoader());
            Object policy = type.getField("INSTANCE").get(null);
            Method open = type.getMethod("openConnection", URL.class);
            Method hash = type.getMethod("spkiHash", X509Certificate.class);
            Method factory = type.getMethod("socketFactory", X509TrustManager.class, Set.class);
            require(((Set<?>) type.getMethod("getBlockedSPKIHashes").invoke(policy)).size() == 12, "expected twelve embedded policy keys");
            TrustManagerFactory managers = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());
            managers.init((KeyStore) null);
            X509TrustManager original = null;
            for (TrustManager manager : managers.getTrustManagers()) {
                if (manager instanceof X509TrustManager) original = (X509TrustManager) manager;
            }
            require(original != null, "native trust manager unavailable");
            URL positive = new URL("https://letsencrypt.org/");
            HttpsURLConnection reference = (HttpsURLConnection) positive.openConnection();
            List<X509Certificate> path;
            try {
                configure(reference);
                require(reference.getResponseCode() == 200, "native reference HTTPS did not succeed");
                Certificate[] supplied = reference.getServerCertificates();
                X509Certificate[] peer = new X509Certificate[supplied.length];
                for (int index = 0; index < supplied.length; index++) peer[index] = (X509Certificate) supplied[index];
                path = new X509TrustManagerExtensions(original).checkServerTrusted(peer, "RSA", positive.getHost());
            } finally { reference.disconnect(); }
            require(path.size() >= 2, "native path did not include an anchor");
            HttpsURLConnection accepted = (HttpsURLConnection) open.invoke(policy, positive);
            try {
                configure(accepted);
                require(!accepted.getInstanceFollowRedirects(), "native image transport must not follow unprotected redirects");
                require(accepted.getResponseCode() == 200, "protected positive HTTPS did not succeed");
            } finally { accepted.disconnect(); }
            for (X509Certificate certificate : new X509Certificate[]{path.get(0), path.get(path.size() - 1)}) {
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
            result.putString("stream", "PASS: actual Atlas APK/native NSC; accepted leaf+anchor denied; twelve public controls rejected; unrelated HTTPS 200; manager=" + original.getClass().getName() + "; controls=" + controls + "\n");
            finish(Activity.RESULT_OK, result);
        } catch (Throwable failure) {
            // Deliberately exclude exception text, URLs, request headers and response bodies.
            result.putString("stream", "FAIL: Atlas certificate control (" + failure.getClass().getSimpleName() + ")\n");
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
