package com.google.devtools.build.lib.remote;

import build.bazel.remote.execution.v2.Digest;
import build.bazel.remote.execution.v2.DigestFunction;
import build.bazel.remote.execution.v2.RequestMetadata;
import build.bazel.remote.execution.v2.ServerCapabilities;
import com.google.bytestream.ByteStreamGrpc;
import com.google.bytestream.ByteStreamProto.*;
import com.google.common.util.concurrent.MoreExecutors;
import com.google.devtools.build.lib.authandtls.CallCredentialsProvider;
import com.google.devtools.build.lib.remote.common.RemoteActionExecutionContext;
import com.google.devtools.build.lib.remote.options.RemoteOptions;
import com.google.devtools.common.options.Options;
import io.grpc.ManagedChannel;
import io.grpc.Server;
import io.grpc.Status;
import io.grpc.netty.NettyChannelBuilder;
import io.grpc.netty.NettyServerBuilder;
import io.grpc.stub.ClientCallStreamObserver;
import io.grpc.stub.ClientResponseObserver;
import io.grpc.stub.StreamObserver;
import io.reactivex.rxjava3.core.Single;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HexFormat;
import java.util.Iterator;
import java.util.List;
import java.util.Random;
import java.util.UUID;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

/** Uses the real uploader bundled in the pinned Bazel binary, not a modeled retry loop. */
public final class UploadRecovery {
  /** Kura's fixed HTTP/2 stream window (HTTP2_STREAM_WINDOW_BYTES in src/app.rs). */
  private static final int KURA_STREAM_WINDOW = 4 * 1024 * 1024;

  private static final int INTERRUPT_AFTER = KURA_STREAM_WINDOW + 2 * 1024 * 1024;

  /** Writes Kura answered from an already stored blob, without staging or storing it again. */
  static long storedBlobWrites(String target) throws Exception {
    // Bazel's embedded runtime has no java.net.http module.
    HttpURLConnection connection =
        (HttpURLConnection) URI.create("http://" + target + "/metrics").toURL().openConnection();
    connection.setConnectTimeout(5_000);
    connection.setReadTimeout(5_000);
    try (InputStream body = connection.getInputStream()) {
      return new String(body.readAllBytes(), StandardCharsets.UTF_8)
          .lines()
          .filter(
              line ->
                  line.startsWith("kura_artifact_writes_total_total{")
                      && line.contains("producer=\"reapi\"")
                      && line.contains("result=\"already_present\""))
          .mapToLong(line -> (long) Double.parseDouble(line.substring(line.lastIndexOf(' ') + 1)))
          .sum();
    } finally {
      connection.disconnect();
    }
  }

  public static void main(String[] args) throws Exception {
    String target = args[0];
    boolean compressed = Boolean.parseBoolean(args[1]);
    byte[] blob = new byte[8 * 1024 * 1024];
    new Random(42).nextBytes(blob);
    String hash = HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(blob));
    String namespace = "bazel/recovery-" + UUID.randomUUID();
    AtomicInteger writes = new AtomicInteger();
    AtomicInteger queries = new AtomicInteger();
    List<Long> firstOffsets = Collections.synchronizedList(new ArrayList<>());
    List<Long> committedSizes = Collections.synchronizedList(new ArrayList<>());
    AtomicReference<String> faultError = new AtomicReference<>();
    ManagedChannel kura = NettyChannelBuilder.forTarget(target).usePlaintext().build();
    ByteStreamGrpc.ByteStreamStub upstreamStub = ByteStreamGrpc.newStub(kura);
    Server proxy =
        NettyServerBuilder.forPort(0)
            .addService(
                new ByteStreamGrpc.ByteStreamImplBase() {
                  @Override
                  public StreamObserver<WriteRequest> write(
                      StreamObserver<WriteResponse> response) {
                    int attempt = writes.incrementAndGet();
                    AtomicBoolean closed = new AtomicBoolean();
                    AtomicReference<ClientCallStreamObserver<WriteRequest>> upstreamCall =
                        new AtomicReference<>();
                    StreamObserver<WriteRequest> upstream =
                        upstreamStub
                            .withDeadlineAfter(30, TimeUnit.SECONDS)
                            .write(
                                new ClientResponseObserver<WriteRequest, WriteResponse>() {
                                  public void beforeStart(
                                      ClientCallStreamObserver<WriteRequest> call) {
                                    upstreamCall.set(call);
                                  }

                                  public void onNext(WriteResponse result) {
                                    committedSizes.add(result.getCommittedSize());
                                    if (!closed.get()) response.onNext(result);
                                  }

                                  public void onError(Throwable error) {
                                    if (closed.compareAndSet(false, true)) response.onError(error);
                                  }

                                  public void onCompleted() {
                                    if (closed.compareAndSet(false, true)) response.onCompleted();
                                  }
                                });
                    return new StreamObserver<>() {
                      long bytes;

                      public void onNext(WriteRequest request) {
                        if (closed.get()) return;
                        if (bytes == 0) firstOffsets.add(request.getWriteOffset());
                        if (request.getWriteOffset() != bytes)
                          throw new AssertionError("offset mismatch");
                        bytes += request.getData().size();
                        upstream.onNext(request);
                        // Force application recovery after exhausting transparent replay's buffer.
                        if (attempt == 1
                            && bytes >= INTERRUPT_AFTER
                            && closed.compareAndSet(false, true)) {
                          // Interrupt only after the forwarded bytes left gRPC's queue. Kura's
                          // stream window admits at most 4 MiB unread, so it has consumed at
                          // least the 2 MiB beyond it.
                          long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(10);
                          while (!upstreamCall.get().isReady() && System.nanoTime() < deadline) {
                            try {
                              Thread.sleep(5);
                            } catch (InterruptedException error) {
                              Thread.currentThread().interrupt();
                              break;
                            }
                          }
                          if (!upstreamCall.get().isReady())
                            faultError.set("Kura never consumed the interrupted upload's prefix");
                          upstream.onError(Status.CANCELLED.asRuntimeException());
                          response.onError(
                              Status.UNAVAILABLE
                                  .withDescription("injected interrupted upload")
                                  .asRuntimeException());
                        }
                      }

                      public void onError(Throwable error) {
                        if (closed.compareAndSet(false, true)) upstream.onError(error);
                      }

                      public void onCompleted() {
                        if (!closed.get()) upstream.onCompleted();
                      }
                    };
                  }

                  @Override
                  public void queryWriteStatus(
                      QueryWriteStatusRequest request,
                      StreamObserver<QueryWriteStatusResponse> response) {
                    queries.incrementAndGet();
                    upstreamStub
                        .withDeadlineAfter(30, TimeUnit.SECONDS)
                        .queryWriteStatus(request, response);
                  }
                })
            .build()
            .start();
    ManagedChannel channel =
        NettyChannelBuilder.forAddress("127.0.0.1", proxy.getPort()).usePlaintext().build();
    ReferenceCountedChannel reference =
        new ReferenceCountedChannel(
            new ChannelConnectionWithServerCapabilitiesFactory() {
              public Single<ChannelConnectionWithServerCapabilities> create() {
                return Single.just(
                    new ChannelConnectionWithServerCapabilities(
                        channel, Single.just(ServerCapabilities.getDefaultInstance())));
              }

              public int maxConcurrency() {
                return 100;
              }
            });
    var scheduler = MoreExecutors.listeningDecorator(Executors.newSingleThreadScheduledExecutor());
    try {
      RemoteRetrier retrier =
          new RemoteRetrier(
              Options.getDefaults(RemoteOptions.class),
              RemoteRetrier.EXPERIMENTAL_GRPC_RESULT_CLASSIFIER,
              scheduler,
              Retrier.ALLOW_ALL_CALLS);
      ByteStreamUploader uploader =
          new ByteStreamUploader(
              namespace,
              reference,
              CallCredentialsProvider.NO_CREDENTIALS,
              30,
              retrier,
              -1,
              DigestFunction.Value.SHA256);
      Digest digest = Digest.newBuilder().setHash(hash).setSizeBytes(blob.length).build();
      uploader
          .uploadBlobAsync(
              RemoteActionExecutionContext.create(RequestMetadata.getDefaultInstance()),
              digest,
              Chunker.builder()
                  .setInput(blob)
                  .setCompressed(compressed)
                  .setChunkSize(128 * 1024)
                  .build())
          .get(60, TimeUnit.SECONDS);
      if (faultError.get() != null) throw new AssertionError(faultError.get());
      if (writes.get() != 2 || queries.get() != 1 || !firstOffsets.equals(List.of(0L, 0L))) {
        throw new AssertionError(
            "expected one interrupted Write, one real status query, and one restart: "
                + writes
                + " "
                + queries
                + " "
                + firstOffsets);
      }
      Iterator<ReadResponse> read =
          ByteStreamGrpc.newBlockingStub(kura)
              .withDeadlineAfter(30, TimeUnit.SECONDS)
              .read(
                  ReadRequest.newBuilder()
                      .setResourceName(namespace + "/blobs/" + hash + "/" + blob.length)
                      .build());
      MessageDigest verification = MessageDigest.getInstance("SHA-256");
      long received = 0;
      while (read.hasNext()) {
        byte[] data = read.next().getData().toByteArray();
        verification.update(data);
        received += data.length;
      }
      if (received != blob.length
          || !Arrays.equals(verification.digest(), HexFormat.of().parseHex(hash))) {
        throw new AssertionError("read-back integrity mismatch");
      }
      System.out.printf(
          "RECOVERY_PASS compressed=%s writes=%d queries=%d offsets=%s verified_bytes=%d%n",
          compressed, writes.get(), queries.get(), firstOffsets, received);

      long storedBefore = storedBlobWrites(target);
      ByteStreamUploader again =
          new ByteStreamUploader(
              namespace,
              reference,
              CallCredentialsProvider.NO_CREDENTIALS,
              30,
              retrier,
              -1,
              DigestFunction.Value.SHA256);
      again
          .uploadBlobAsync(
              RemoteActionExecutionContext.create(RequestMetadata.getDefaultInstance()),
              digest,
              Chunker.builder()
                  .setInput(blob)
                  .setCompressed(compressed)
                  .setChunkSize(128 * 1024)
                  .build())
          .get(60, TimeUnit.SECONDS);
      long storedCommitted = committedSizes.get(committedSizes.size() - 1);
      long storedWrites = storedBlobWrites(target) - storedBefore;
      if (writes.get() != 3
          || storedWrites != 1
          || (!compressed && storedCommitted != blob.length)) {
        throw new AssertionError(
            "expected one Write answered from the stored blob: "
                + writes
                + " "
                + storedWrites
                + " "
                + committedSizes);
      }
      System.out.printf(
          "STORED_PASS compressed=%s writes=%d answered_from_stored=%d%n",
          compressed, writes.get() - 2, storedWrites);
    } finally {
      reference.release();
      channel.shutdownNow().awaitTermination(5, TimeUnit.SECONDS);
      proxy.shutdownNow().awaitTermination(5, TimeUnit.SECONDS);
      kura.shutdownNow().awaitTermination(5, TimeUnit.SECONDS);
      scheduler.shutdownNow();
    }
  }
}
