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
import io.grpc.stub.StreamObserver;
import io.reactivex.rxjava3.core.Single;
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

/** Uses the real uploader bundled in the pinned Bazel binary, not a modeled retry loop. */
public final class UploadRecovery {
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
                    StreamObserver<WriteRequest> upstream =
                        upstreamStub
                            .withDeadlineAfter(30, TimeUnit.SECONDS)
                            .write(
                                new StreamObserver<>() {
                                  public void onNext(WriteResponse result) {
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
                            && bytes >= 2 * 1024 * 1024
                            && closed.compareAndSet(false, true)) {
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
    } finally {
      reference.release();
      channel.shutdownNow().awaitTermination(5, TimeUnit.SECONDS);
      proxy.shutdownNow().awaitTermination(5, TimeUnit.SECONDS);
      kura.shutdownNow().awaitTermination(5, TimeUnit.SECONDS);
      scheduler.shutdownNow();
    }
  }
}
