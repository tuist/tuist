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

type tlsPublicConnectionRetirer struct {
	dialContext func(context.Context, string, string) (net.Conn, error)
}

func (r tlsPublicConnectionRetirer) post(ctx context.Context, pod corev1.Pod, serverName, path string, tlsData map[string][]byte, payload, receipt any) error {
	cert, err := tls.X509KeyPair(tlsData[peerTLSCertFile], tlsData[peerTLSKeyFile])
	if err != nil {
		return fmt.Errorf("load peer client certificate: %w", err)
	}
	roots := x509.NewCertPool()
	if !roots.AppendCertsFromPEM(tlsData[peerTLSCAFile]) {
		return fmt.Errorf("load peer certificate authority")
	}
	transport := &http.Transport{DialContext: r.dialContext, TLSClientConfig: &tls.Config{Certificates: []tls.Certificate{cert}, RootCAs: roots, ServerName: serverName, MinVersion: tls.VersionTLS12}}
	defer transport.CloseIdleConnections()
	body, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, "https://"+net.JoinHostPort(pod.Status.PodIP, strconv.Itoa(int(peerPort)))+path, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	response, err := (&http.Client{Transport: transport, Timeout: 5 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}).Do(req)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return fmt.Errorf("%s returned HTTP %d", path, response.StatusCode)
	}
	return json.NewDecoder(io.LimitReader(response.Body, 4096)).Decode(receipt)
}

func (r tlsPublicConnectionRetirer) Retire(ctx context.Context, pod corev1.Pod, serverName, incarnation string, tlsData map[string][]byte) (bool, error) {
	var receipt struct {
		Incarnation string  `json:"incarnation"`
		Remaining   *uint64 `json:"remaining_connections"`
	}
	err := r.post(ctx, pod, serverName, "/_internal/connections/retire", tlsData, map[string]string{"incarnation": incarnation}, &receipt)
	if err != nil {
		return false, err
	}
	if receipt.Incarnation != incarnation || receipt.Remaining == nil {
		return false, fmt.Errorf("invalid connection retirement receipt")
	}
	return *receipt.Remaining == 0, nil
}

type migrationTarget struct {
	URL         string `json:"url"`
	Incarnation string `json:"incarnation"`
}

type migrationPreparer interface {
	Prepare(context.Context, corev1.Pod, string, string, migrationTarget, map[string][]byte) (bool, error)
	Rebind(context.Context, corev1.Pod, string, string, migrationTarget, migrationTarget, map[string][]byte) error
	Abort(context.Context, corev1.Pod, string, string, migrationTarget, map[string][]byte) error
}

func (r tlsPublicConnectionRetirer) Rebind(ctx context.Context, pod corev1.Pod, serverName, incarnation string, target, replacement migrationTarget, tlsData map[string][]byte) error {
	var receipt struct {
		Incarnation string          `json:"incarnation"`
		Target      migrationTarget `json:"target"`
	}
	err := r.post(ctx, pod, serverName, "/_internal/migration/rebind", tlsData, struct {
		Incarnation string          `json:"incarnation"`
		Target      migrationTarget `json:"target"`
		Replacement migrationTarget `json:"replacement"`
	}{incarnation, target, replacement}, &receipt)
	if err != nil {
		return err
	}
	if receipt.Incarnation != incarnation || receipt.Target != replacement {
		return fmt.Errorf("invalid migration rebind receipt")
	}
	return nil
}

func (r tlsPublicConnectionRetirer) Abort(ctx context.Context, pod corev1.Pod, serverName, incarnation string, target migrationTarget, tlsData map[string][]byte) error {
	var receipt struct {
		Incarnation string `json:"incarnation"`
		Aborted     bool   `json:"aborted"`
	}
	err := r.post(ctx, pod, serverName, "/_internal/migration/abort", tlsData, struct {
		Incarnation string          `json:"incarnation"`
		Target      migrationTarget `json:"target"`
	}{incarnation, target}, &receipt)
	if err != nil {
		return err
	}
	if receipt.Incarnation != incarnation || !receipt.Aborted {
		return fmt.Errorf("invalid migration abort receipt")
	}
	return nil
}

func (r tlsPublicConnectionRetirer) Prepare(ctx context.Context, pod corev1.Pod, serverName, incarnation string, target migrationTarget, tlsData map[string][]byte) (bool, error) {
	var receipt struct {
		Incarnation string          `json:"incarnation"`
		Target      migrationTarget `json:"target"`
		Ready       *bool           `json:"ready"`
	}
	err := r.post(ctx, pod, serverName, "/_internal/migration/prepare", tlsData, struct {
		Incarnation string          `json:"incarnation"`
		Target      migrationTarget `json:"target"`
	}{incarnation, target}, &receipt)
	if err != nil {
		return false, err
	}
	if receipt.Incarnation != incarnation || receipt.Target != target || receipt.Ready == nil {
		return false, fmt.Errorf("invalid migration preparation receipt")
	}
	return *receipt.Ready, nil
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
