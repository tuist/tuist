package controllers

import (
	"bytes"
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"strconv"
	"time"

	kurav1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	corev1 "k8s.io/api/core/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

type PublicConnectionRetirer interface {
	Retire(context.Context, corev1.Pod, string, string, map[string][]byte) (bool, error)
}

type tlsPublicConnectionRetirer struct{}

func (tlsPublicConnectionRetirer) Retire(ctx context.Context, pod corev1.Pod, serverName, incarnation string, tlsData map[string][]byte) (bool, error) {
	cert, err := tls.X509KeyPair(tlsData[peerTLSCertFile], tlsData[peerTLSKeyFile])
	if err != nil {
		return false, fmt.Errorf("load peer client certificate: %w", err)
	}
	roots := x509.NewCertPool()
	if !roots.AppendCertsFromPEM(tlsData[peerTLSCAFile]) {
		return false, fmt.Errorf("load peer certificate authority")
	}
	transport := &http.Transport{TLSClientConfig: &tls.Config{Certificates: []tls.Certificate{cert}, RootCAs: roots, ServerName: serverName, MinVersion: tls.VersionTLS12}}
	defer transport.CloseIdleConnections()
	body, err := json.Marshal(map[string]string{"incarnation": incarnation})
	if err != nil {
		return false, err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, "https://"+net.JoinHostPort(pod.Status.PodIP, strconv.Itoa(int(peerPort)))+"/_internal/connections/retire", bytes.NewReader(body))
	if err != nil {
		return false, err
	}
	req.Header.Set("Content-Type", "application/json")
	response, err := (&http.Client{Transport: transport, Timeout: 5 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}).Do(req)
	if err != nil {
		return false, err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return false, fmt.Errorf("connection retirement returned HTTP %d", response.StatusCode)
	}
	var receipt struct {
		Incarnation string  `json:"incarnation"`
		Remaining   *uint64 `json:"remaining_connections"`
	}
	if err = json.NewDecoder(io.LimitReader(response.Body, 4096)).Decode(&receipt); err != nil {
		return false, err
	}
	if receipt.Incarnation != incarnation || receipt.Remaining == nil {
		return false, fmt.Errorf("invalid connection retirement receipt")
	}
	return *receipt.Remaining == 0, nil
}

// Service handoff does not move existing TCP connections. Before deleting a thin
// migration donor, ask its current process to finish old HTTP connections with
// Connection: close while it still serves and replicates. A zero receipt is
// required; an old runtime, a failed probe or a restarted process is not success.
func (r *KuraInstanceReconciler) lvmConnectionsRetired(ctx context.Context, instance *kurav1.KuraInstance, pod *corev1.Pod) (bool, error) {
	if instance.Spec.StorageClassName != thinLocalStorageClass {
		return true, nil
	}
	status, err := r.runtimeStatusClient(instance).Status(ctx, *pod)
	if err != nil || status.invalidObservation || status.ConnectionIncarnation == "" || pod.Status.PodIP == "" {
		return false, err
	}
	secret := &corev1.Secret{}
	if err := r.Get(ctx, client.ObjectKey{Namespace: instance.Namespace, Name: peerTLSSecretName(instance)}, secret); err != nil {
		return false, err
	}
	retirer := r.PublicConnectionRetirer
	if retirer == nil {
		retirer = tlsPublicConnectionRetirer{}
	}
	serverName := fmt.Sprintf("%s-headless.%s.svc.cluster.local", instance.Name, instance.Namespace)
	return retirer.Retire(ctx, *pod, serverName, status.ConnectionIncarnation, secret.Data)
}
