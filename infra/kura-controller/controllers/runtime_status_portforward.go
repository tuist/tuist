package controllers

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"time"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/util/httpstream"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/portforward"
	"k8s.io/client-go/transport/spdy"
)

// runtimeStatusTimeout bounds one /status/rollout sample, however the pod is
// reached.
const runtimeStatusTimeout = 2 * time.Second

type unavailableRuntimeStatusClient struct {
	reason string
}

func (c unavailableRuntimeStatusClient) Status(context.Context, corev1.Pod) (runtimeStatus, error) {
	return runtimeStatus{}, errors.New(c.reason)
}

// portForwardRuntimeStatusClient reads /status/rollout through the API
// server's pod port-forward, which reaches the pod through its node's kubelet.
// It serves pods whose IP the controller cannot route to.
type portForwardRuntimeStatusClient struct {
	config  *rest.Config
	rest    rest.Interface
	timeout time.Duration
}

func NewPortForwardRuntimeStatusClient(config *rest.Config) (RuntimeStatusClient, error) {
	config = rest.CopyConfig(config)
	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		return nil, err
	}
	return &portForwardRuntimeStatusClient{
		config:  config,
		rest:    clientset.CoreV1().RESTClient(),
		timeout: runtimeStatusTimeout,
	}, nil
}

func (c *portForwardRuntimeStatusClient) Status(ctx context.Context, pod corev1.Pod) (runtimeStatus, error) {
	ctx, cancel := context.WithTimeout(ctx, c.timeout)
	defer cancel()

	target := c.rest.Post().
		Resource("pods").
		Namespace(pod.Namespace).
		Name(pod.Name).
		SubResource("portforward").
		URL()
	dialer, err := c.dialer(target)
	if err != nil {
		return runtimeStatus{}, err
	}
	connection, err := dialStreamConnection(ctx, dialer)
	if err != nil {
		return runtimeStatus{}, fmt.Errorf("port-forward to %s/%s: %w", pod.Namespace, pod.Name, err)
	}
	defer connection.Close()
	stop := context.AfterFunc(ctx, func() { _ = connection.Close() })
	defer stop()

	status, err := requestRuntimeStatusOverStream(ctx, connection, httpPort)
	if err != nil && ctx.Err() != nil {
		return runtimeStatus{}, ctx.Err()
	}
	return status, err
}

// dialer prefers the WebSocket transport and falls back to SPDY on an API
// server that does not upgrade port-forward over WebSockets, as kubectl does.
func (c *portForwardRuntimeStatusClient) dialer(target *url.URL) (httpstream.Dialer, error) {
	transport, upgrader, err := spdy.RoundTripperFor(c.config)
	if err != nil {
		return nil, err
	}
	spdyDialer := spdy.NewDialer(upgrader, &http.Client{Transport: transport}, http.MethodPost, target)
	websocketDialer, err := portforward.NewSPDYOverWebsocketDialer(target, c.config)
	if err != nil {
		return nil, err
	}
	return portforward.NewFallbackDialer(websocketDialer, spdyDialer, func(err error) bool {
		return httpstream.IsUpgradeFailure(err) || httpstream.IsHTTPSProxyError(err)
	}), nil
}

// dialStreamConnection bounds a dial that takes no context. A connection that
// arrives after the deadline is closed.
func dialStreamConnection(ctx context.Context, dialer httpstream.Dialer) (httpstream.Connection, error) {
	type dialResult struct {
		connection httpstream.Connection
		err        error
	}
	done := make(chan dialResult, 1)
	go func() {
		connection, _, err := dialer.Dial(portforward.PortForwardProtocolV1Name)
		done <- dialResult{connection: connection, err: err}
	}()
	select {
	case result := <-done:
		return result.connection, result.err
	case <-ctx.Done():
		go func() {
			if result := <-done; result.connection != nil {
				_ = result.connection.Close()
			}
		}()
		return nil, ctx.Err()
	}
}

// requestRuntimeStatusOverStream sends one GET /status/rollout over a
// port-forward connection, using the error and data stream pair the
// port-forward protocol opens per forwarded connection.
func requestRuntimeStatusOverStream(ctx context.Context, connection httpstream.Connection, port int32) (runtimeStatus, error) {
	headers := http.Header{}
	headers.Set(corev1.StreamType, corev1.StreamTypeError)
	headers.Set(corev1.PortHeader, strconv.Itoa(int(port)))
	headers.Set(corev1.PortForwardRequestIDHeader, "0")
	errorStream, err := connection.CreateStream(headers)
	if err != nil {
		return runtimeStatus{}, fmt.Errorf("creating error stream: %w", err)
	}
	_ = errorStream.Close()
	defer connection.RemoveStreams(errorStream)

	forwardErr := make(chan error, 1)
	go func() {
		message, err := io.ReadAll(errorStream)
		switch {
		case err != nil:
			forwardErr <- fmt.Errorf("reading error stream: %w", err)
		case len(message) > 0:
			forwardErr <- fmt.Errorf("forwarding port %d: %s", port, message)
		default:
			forwardErr <- nil
		}
	}()

	headers.Set(corev1.StreamType, corev1.StreamTypeData)
	dataStream, err := connection.CreateStream(headers)
	if err != nil {
		return runtimeStatus{}, fmt.Errorf("creating data stream: %w", err)
	}
	defer connection.RemoveStreams(dataStream)
	defer func() { _ = dataStream.Reset() }()

	request, err := http.NewRequestWithContext(ctx, http.MethodGet, fmt.Sprintf("http://localhost:%d/status/rollout", port), nil)
	if err != nil {
		return runtimeStatus{}, err
	}
	request.Close = true
	if err := request.Write(dataStream); err != nil {
		return runtimeStatus{}, forwardError(ctx, forwardErr, err)
	}
	response, err := http.ReadResponse(bufio.NewReader(dataStream), request)
	if err != nil {
		return runtimeStatus{}, forwardError(ctx, forwardErr, err)
	}
	return decodeRuntimeStatus(response)
}

// forwardError prefers the reason the kubelet reported on the error stream,
// such as a refused pod port, over the bare stream error it causes.
func forwardError(ctx context.Context, forwardErr <-chan error, streamErr error) error {
	select {
	case err := <-forwardErr:
		if err != nil {
			return err
		}
	case <-ctx.Done():
	}
	return streamErr
}
