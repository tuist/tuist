package controllers

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
)

type runtimeStatusResponseError struct {
	cause error
}

func (e *runtimeStatusResponseError) Error() string { return e.cause.Error() }
func (e *runtimeStatusResponseError) Unwrap() error { return e.cause }

func observedRuntimeStatus(status runtimeStatus, err error) (runtimeStatus, bool) {
	if err == nil {
		return status, true
	}
	var responseError *runtimeStatusResponseError
	if errors.As(err, &responseError) {
		return runtimeStatus{invalidObservation: true}, true
	}
	return runtimeStatus{}, false
}

func decodeRuntimeStatus(resp *http.Response) (runtimeStatus, error) {
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return runtimeStatus{}, &runtimeStatusResponseError{cause: fmt.Errorf("unexpected runtime status %d", resp.StatusCode)}
	}
	var status *runtimeStatus
	if err := json.NewDecoder(resp.Body).Decode(&status); err != nil {
		var syntax *json.SyntaxError
		var mismatch *json.UnmarshalTypeError
		if errors.As(err, &syntax) || errors.As(err, &mismatch) || errors.Is(err, io.EOF) {
			return runtimeStatus{}, &runtimeStatusResponseError{cause: err}
		}
		return runtimeStatus{}, err
	}
	if status == nil {
		return runtimeStatus{}, &runtimeStatusResponseError{cause: errors.New("runtime status must be an object")}
	}
	return *status, nil
}
