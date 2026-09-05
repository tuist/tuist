package controllers

import (
	"context"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	apilabels "k8s.io/apimachinery/pkg/labels"
	"k8s.io/client-go/rest"
	metricsclient "k8s.io/metrics/pkg/client/clientset/versioned"
)

type metricsServerClient struct {
	client metricsclient.Interface
}

// NewPodMetricsClient reads pod CPU from the metrics.k8s.io aggregated API.
// It bypasses the manager's cached client because that API serves a computed
// view with no resourceVersion and no watch, so it cannot back an informer.
func NewPodMetricsClient(config *rest.Config) (PodMetricsClient, error) {
	client, err := metricsclient.NewForConfig(config)
	if err != nil {
		return nil, err
	}
	return &metricsServerClient{client: client}, nil
}

func (m *metricsServerClient) PodCPUMilli(ctx context.Context, namespace string, selector map[string]string) (map[string]int64, error) {
	list, err := m.client.MetricsV1beta1().PodMetricses(namespace).List(ctx, metav1.ListOptions{
		LabelSelector: apilabels.SelectorFromSet(selector).String(),
	})
	if err != nil {
		return nil, err
	}

	usage := make(map[string]int64, len(list.Items))
	for i := range list.Items {
		var total int64
		for _, container := range list.Items[i].Containers {
			total += container.Usage.Cpu().MilliValue()
		}
		usage[list.Items[i].Name] = total
	}
	return usage, nil
}
