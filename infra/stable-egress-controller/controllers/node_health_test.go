package controllers

import (
	"context"
	"net"
	"strconv"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

func TestDirectNodeHealthChecker(t *testing.T) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_ = listener.Close()
	})

	port := listener.Addr().(*net.TCPAddr).Port
	checker := DirectNodeHealthChecker{Port: port, Timeout: time.Second}
	node := &corev1.Node{
		Status: corev1.NodeStatus{
			Addresses: []corev1.NodeAddress{
				{Type: corev1.NodeInternalIP, Address: "127.0.0.1"},
			},
		},
	}

	healthy, err := checker.Healthy(context.Background(), node)
	if err != nil {
		t.Fatal(err)
	}
	if !healthy {
		t.Fatal("expected the listening node to be healthy")
	}
}

func TestDirectNodeHealthCheckerReportsClosedPort(t *testing.T) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	port := listener.Addr().(*net.TCPAddr).Port
	if err := listener.Close(); err != nil {
		t.Fatal(err)
	}

	checker := DirectNodeHealthChecker{Port: port, Timeout: 100 * time.Millisecond}
	node := &corev1.Node{
		ObjectMeta: metav1.ObjectMeta{Name: "egress-a"},
		Status: corev1.NodeStatus{
			Addresses: []corev1.NodeAddress{
				{Type: corev1.NodeInternalIP, Address: "127.0.0.1"},
			},
		},
	}

	healthy, err := checker.Healthy(context.Background(), node)
	if err == nil {
		t.Fatal("expected a closed port error")
	}
	if healthy {
		t.Fatal("expected the node with closed port " + strconv.Itoa(port) + " to be unhealthy")
	}
}

func TestDirectNodeHealthCheckerFallsBackToExternalAddress(t *testing.T) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_ = listener.Close()
	})

	port := listener.Addr().(*net.TCPAddr).Port
	checker := DirectNodeHealthChecker{Port: port, Timeout: time.Second}
	node := &corev1.Node{
		Status: corev1.NodeStatus{
			Addresses: []corev1.NodeAddress{
				{Type: corev1.NodeInternalIP, Address: "127.0.0.2"},
				{Type: corev1.NodeExternalIP, Address: "127.0.0.1"},
			},
		},
	}

	healthy, err := checker.Healthy(context.Background(), node)
	if err != nil {
		t.Fatal(err)
	}
	if !healthy {
		t.Fatal("expected the external-address fallback to succeed")
	}
}

func TestDirectNodeHealthCheckerRequiresAddress(t *testing.T) {
	checker := DirectNodeHealthChecker{Port: 9962, Timeout: time.Second}
	node := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "egress-a"}}

	healthy, err := checker.Healthy(context.Background(), node)
	if err == nil {
		t.Fatal("expected a missing-address error")
	}
	if healthy {
		t.Fatal("expected a node without an address to be unhealthy")
	}
}
