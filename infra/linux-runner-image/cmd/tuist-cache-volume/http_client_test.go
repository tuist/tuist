package main

import "net/http"

func attachWithClient(key string, targets []string, root string, size int64, client *http.Client) error {
	return attachWithMounter(key, targets, root, size, client, bindDirectory)
}

func attachWithMounter(key string, targets []string, root string, size int64, client *http.Client, mount func(string, string, string) error) error {
	return attachUsing(key, targets, root, func() (string, string, bool, error) { return acquire(client, key, size) }, mount)
}
