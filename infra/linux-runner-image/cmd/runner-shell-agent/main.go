package main

import (
	"context"
	"crypto/tls"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	osuser "os/user"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/creack/pty"
	"github.com/gorilla/websocket"
)

const (
	defaultUserAgent          = "curl/8.7.1"
	maxDiscoveryResponseBytes = 64 * 1024
	maxWebSocketMessageBytes  = 1024 * 1024
	maxTerminalDimension      = 1000
)

const (
	localFrameStdin byte = iota + 1
	localFrameStdout
	localFrameResize
	localFrameExit
	localFrameClose
)

var tokenPaths = []string{
	"/etc/tuist-sa-token",
	"/var/run/secrets/tuist-runner/token",
}

var directHTTPTransport = &http.Transport{
	Proxy:           nil,
	DialContext:     (&net.Dialer{Timeout: 10 * time.Second, KeepAlive: 30 * time.Second}).DialContext,
	TLSClientConfig: &tls.Config{MinVersion: tls.VersionTLS12},
	IdleConnTimeout: 30 * time.Second,
}

var directHTTPClientInstance = &http.Client{
	Timeout:   10 * time.Second,
	Transport: directHTTPTransport,
}

type runnerSession struct {
	SessionID     int    `json:"session_id"`
	WorkflowJobID int    `json:"workflow_job_id"`
	WebSocketURL  string `json:"websocket_url"`
}

type textFrame struct {
	Type    string `json:"type"`
	Status  string `json:"status"`
	Columns int    `json:"columns"`
	Rows    int    `json:"rows"`
}

type exitFrame struct {
	Type   string `json:"type"`
	Status int    `json:"status"`
}

type shellUser struct {
	Name   string
	UID    uint32
	GID    uint32
	UIDInt int
	GIDInt int
	Groups []uint32
	Home   string
	Shell  string
}

type spawnedShell struct {
	Command *exec.Cmd
	PTY     *os.File
	Cleanup func()
}

type wsMessage struct {
	Type    int
	Payload []byte
	Err     error
}

type ptyMessage struct {
	Payload []byte
	Err     error
}

type localShellFrame struct {
	Type    byte
	Payload []byte
	Err     error
}

func main() {
	if os.Getenv("TUIST_RUNNER_SHELL_PTY_SERVER") == "1" {
		if err := serveLocalShellSocket(localShellSocketPath()); err != nil {
			logf("local shell socket server failed: %v", err)
			os.Exit(1)
		}
		return
	}

	defer closeDirectHTTPIdleConnections()

	if os.Getenv("TUIST_RUNNER_DISPATCH_URL") == "" {
		logf("TUIST_RUNNER_DISPATCH_URL unset; shell agent disabled")
		os.Exit(0)
	}

	waitForClaim()

	discovery, err := discoveryURL()
	if err != nil {
		logf("invalid discovery url: %v", err)
		os.Exit(1)
	}

	logf("polling shell sessions at %s", discovery)

	for {
		token, err := readToken()
		if err != nil {
			logf("token read failed: %v", err)
			time.Sleep(2 * time.Second)
			continue
		}

		session, err := discoverSession(discovery, token)
		if err != nil {
			logf("session discovery failed: %v", err)
			time.Sleep(2 * time.Second)
			continue
		}

		if session != nil {
			if err := bridgeSession(*session, token, discovery); err != nil {
				logf("shell bridge failed: %v", err)
			}
		}

		time.Sleep(2 * time.Second)
	}
}

func logf(format string, args ...any) {
	message := fmt.Sprintf(format, args...)
	fmt.Printf("%s runner-shell-agent: %s\n", time.Now().UTC().Format("2006-01-02T15:04:05Z"), message)
}

func tokenPath() string {
	if configured := os.Getenv("TUIST_RUNNER_TOKEN_PATH"); configured != "" {
		return configured
	}

	for _, path := range tokenPaths {
		if _, err := os.Stat(path); err == nil {
			return path
		}
	}

	return tokenPaths[len(tokenPaths)-1]
}

func readToken() (string, error) {
	contents, err := os.ReadFile(tokenPath())
	if err != nil {
		return "", err
	}

	token := strings.TrimSpace(string(contents))
	if token == "" {
		return "", errors.New("token file is empty")
	}

	return token, nil
}

func discoveryURL() (string, error) {
	if configured := os.Getenv("TUIST_RUNNER_SHELL_DISCOVERY_URL"); configured != "" {
		return configured, nil
	}

	baseURL := strings.TrimRight(os.Getenv("TUIST_RUNNER_DISPATCH_URL"), "/")
	if baseURL == "" {
		return "", errors.New("TUIST_RUNNER_DISPATCH_URL is empty")
	}

	if strings.HasSuffix(baseURL, "/dispatch") {
		baseURL = strings.TrimSuffix(baseURL, "/dispatch")
	}

	return baseURL + "/interactive/shell/sessions", nil
}

func waitForClaim() {
	claimMarkerPath := os.Getenv("TUIST_RUNNER_JIT_PATH")
	if claimMarkerPath == "" {
		claimMarkerPath = os.Getenv("TUIST_RUNNER_SHELL_CLAIM_MARKER")
	}
	if claimMarkerPath == "" {
		return
	}

	logf("waiting for a claimed job (marker at %s) before accepting shell sessions", claimMarkerPath)
	for {
		if _, err := os.Stat(claimMarkerPath); err == nil {
			return
		}
		time.Sleep(time.Second)
	}
}

func directHTTPClient() *http.Client {
	return directHTTPClientInstance
}

func closeDirectHTTPIdleConnections() {
	directHTTPTransport.CloseIdleConnections()
}

func discoverSession(discovery string, token string) (*runnerSession, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	request, err := http.NewRequestWithContext(ctx, http.MethodGet, discovery, nil)
	if err != nil {
		return nil, err
	}

	request.Header.Set("Authorization", "Bearer "+token)
	request.Header.Set("User-Agent", userAgent())

	if podName := os.Getenv("TUIST_RUNNER_POD_NAME"); podName != "" {
		request.Header.Set("X-Tuist-Runner-Pod-Name", podName)
	}
	if podUID := os.Getenv("TUIST_RUNNER_POD_UID"); podUID != "" {
		request.Header.Set("X-Tuist-Runner-Pod-Uid", podUID)
	}
	if pool := os.Getenv("TUIST_RUNNER_POOL"); pool != "" {
		request.Header.Set("X-Tuist-Runner-Pool", pool)
	}

	response, err := directHTTPClient().Do(request)
	if err != nil {
		return nil, err
	}
	defer response.Body.Close()

	if response.StatusCode == http.StatusNoContent || response.StatusCode == http.StatusNotFound {
		return nil, nil
	}

	if response.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(response.Body, 300))
		detail := strings.TrimSpace(strings.ReplaceAll(string(body), "\n", " "))
		if detail != "" {
			logf("session discovery returned HTTP %d: %s", response.StatusCode, detail)
		} else {
			logf("session discovery returned HTTP %d", response.StatusCode)
		}
		return nil, nil
	}

	var session runnerSession
	decoder := json.NewDecoder(io.LimitReader(response.Body, maxDiscoveryResponseBytes))
	if err := decoder.Decode(&session); err != nil {
		return nil, err
	}

	if session.SessionID <= 0 || session.WebSocketURL == "" {
		return nil, errors.New("server returned an incomplete shell session")
	}

	return &session, nil
}

func sessionWebSocketURL(session runnerSession, discovery string) (string, error) {
	rawURL := session.WebSocketURL
	if os.Getenv("TUIST_RUNNER_SHELL_USE_DISCOVERY_ORIGIN") == "0" {
		return rawURL, nil
	}

	discovered, err := url.Parse(discovery)
	if err != nil {
		return "", err
	}

	websocketURL, err := url.Parse(rawURL)
	if err != nil {
		return "", err
	}

	scheme := "ws"
	if discovered.Scheme == "https" {
		scheme = "wss"
	}

	websocketURL.Scheme = scheme
	websocketURL.Host = discovered.Host
	return websocketURL.String(), nil
}

func connectWebSocket(rawURL string, token string) (*websocket.Conn, error) {
	parsed, err := url.Parse(rawURL)
	if err != nil {
		return nil, err
	}

	if parsed.Scheme != "ws" && parsed.Scheme != "wss" {
		return nil, fmt.Errorf("unsupported websocket scheme: %s", parsed.Scheme)
	}

	dialer := &websocket.Dialer{
		HandshakeTimeout: 10 * time.Second,
		Proxy:            nil,
		TLSClientConfig:  &tls.Config{MinVersion: tls.VersionTLS12},
		NetDialContext:   (&net.Dialer{Timeout: 10 * time.Second, KeepAlive: 30 * time.Second}).DialContext,
	}

	headers := http.Header{}
	headers.Set("Authorization", "Bearer "+token)
	headers.Set("User-Agent", userAgent())
	headers.Set("Accept", "*/*")
	headers.Set("Origin", originFor(parsed))

	conn, response, err := dialer.Dial(rawURL, headers)
	if err != nil {
		if response != nil {
			defer response.Body.Close()
			body, _ := io.ReadAll(io.LimitReader(response.Body, 300))
			detail := strings.TrimSpace(strings.ReplaceAll(string(body), "\n", " "))
			if detail != "" {
				return nil, fmt.Errorf("websocket handshake failed: %s: %s", response.Status, detail)
			}
			return nil, fmt.Errorf("websocket handshake failed: %s", response.Status)
		}
		return nil, err
	}

	conn.SetReadLimit(maxWebSocketMessageBytes)
	return conn, nil
}

func originFor(parsed *url.URL) string {
	scheme := "http"
	if parsed.Scheme == "wss" {
		scheme = "https"
	}
	return scheme + "://" + parsed.Host
}

func userAgent() string {
	if configured := os.Getenv("TUIST_RUNNER_SHELL_USER_AGENT"); configured != "" {
		return configured
	}
	return defaultUserAgent
}

func bridgeSession(session runnerSession, token string, discovery string) error {
	webSocketURL, err := sessionWebSocketURL(session, discovery)
	if err != nil {
		return err
	}

	logf("connecting shell tunnel for session %d -> %s", session.SessionID, webSocketURL)
	conn, err := connectWebSocket(webSocketURL, token)
	if err != nil {
		return err
	}
	defer conn.Close()

	if socketPath := localShellSocketPath(); socketPath != "" {
		return bridgeRemoteShellSession(session, conn, socketPath)
	}

	return bridgeLocalShellSession(session, conn)
}

func bridgeLocalShellSession(session runnerSession, conn *websocket.Conn) error {
	shell, err := spawnShell()
	if err != nil {
		return err
	}
	defer shell.Cleanup()

	wsCh := make(chan wsMessage, 1)
	ptyCh := make(chan ptyMessage, 1)
	waitCh := make(chan int, 1)

	go readWebSocket(conn, wsCh)
	go readPTY(shell.PTY, ptyCh)
	go func() { waitCh <- commandExitStatus(shell.Command.Wait()) }()

	for {
		select {
		case message := <-wsCh:
			if message.Err != nil {
				return nil
			}

			switch message.Type {
			case websocket.TextMessage:
				action := handleTextFrame(shell.PTY, message.Payload)
				if action == "client_disconnected" {
					logf("client disconnected; closing shell tunnel for session %d", session.SessionID)
					return nil
				}
			case websocket.BinaryMessage:
				if _, err := shell.PTY.Write(message.Payload); err != nil {
					return err
				}
			}

		case message := <-ptyCh:
			if message.Err != nil {
				status := waitForExitStatus(waitCh, 2*time.Second, 0)
				_ = sendShellExit(conn, status)
				return nil
			}

			if err := writeWebSocketMessage(conn, websocket.BinaryMessage, message.Payload); err != nil {
				return err
			}

		case status := <-waitCh:
			_ = sendShellExit(conn, status)
			return nil
		}
	}
}

func bridgeRemoteShellSession(session runnerSession, conn *websocket.Conn, socketPath string) error {
	shellConn, err := net.DialTimeout("unix", socketPath, 5*time.Second)
	if err != nil {
		return fmt.Errorf("connect local runner shell socket: %w", err)
	}
	defer shellConn.Close()

	wsCh := make(chan wsMessage, 1)
	shellCh := make(chan localShellFrame, 1)

	go readWebSocket(conn, wsCh)
	go readLocalShellFrames(shellConn, shellCh)

	for {
		select {
		case message := <-wsCh:
			if message.Err != nil {
				return nil
			}

			switch message.Type {
			case websocket.TextMessage:
				action := handleTextFramePayload(message.Payload)
				if action == "client_disconnected" {
					_ = writeLocalShellFrame(shellConn, localFrameClose, nil)
					logf("client disconnected; closing shell tunnel for session %d", session.SessionID)
					return nil
				}
				if action == "resize" {
					if err := writeLocalShellFrame(shellConn, localFrameResize, message.Payload); err != nil {
						return err
					}
				}
			case websocket.BinaryMessage:
				if err := writeLocalShellFrame(shellConn, localFrameStdin, message.Payload); err != nil {
					return err
				}
			}

		case message := <-shellCh:
			if message.Err != nil {
				_ = sendShellExit(conn, 255)
				return nil
			}

			switch message.Type {
			case localFrameStdout:
				if err := writeWebSocketMessage(conn, websocket.BinaryMessage, message.Payload); err != nil {
					return err
				}
			case localFrameExit:
				status := 0
				var frame exitFrame
				if err := json.Unmarshal(message.Payload, &frame); err == nil {
					status = frame.Status
				}
				_ = sendShellExit(conn, status)
				return nil
			}
		}
	}
}

func readWebSocket(conn *websocket.Conn, ch chan<- wsMessage) {
	for {
		messageType, payload, err := conn.ReadMessage()
		if err != nil {
			ch <- wsMessage{Err: err}
			return
		}
		ch <- wsMessage{Type: messageType, Payload: payload}
	}
}

func readPTY(file *os.File, ch chan<- ptyMessage) {
	buffer := make([]byte, 8192)
	for {
		n, err := file.Read(buffer)
		if n > 0 {
			payload := make([]byte, n)
			copy(payload, buffer[:n])
			ch <- ptyMessage{Payload: payload}
		}
		if err != nil {
			ch <- ptyMessage{Err: err}
			return
		}
	}
}

func sendShellExit(conn *websocket.Conn, status int) error {
	payload, err := json.Marshal(exitFrame{Type: "exit", Status: status})
	if err != nil {
		return err
	}

	return writeWebSocketMessage(conn, websocket.TextMessage, payload)
}

func writeWebSocketMessage(conn *websocket.Conn, messageType int, payload []byte) error {
	if err := conn.SetWriteDeadline(time.Now().Add(10 * time.Second)); err != nil {
		return err
	}
	return conn.WriteMessage(messageType, payload)
}

func handleTextFrame(ptyFile *os.File, payload []byte) string {
	action := handleTextFramePayload(payload)
	if action != "resize" {
		return action
	}

	var message textFrame
	if err := json.Unmarshal(payload, &message); err != nil {
		return ""
	}

	_ = pty.Setsize(ptyFile, &pty.Winsize{Cols: uint16(message.Columns), Rows: uint16(message.Rows)})
	return ""
}

func handleTextFramePayload(payload []byte) string {
	var message textFrame
	if err := json.Unmarshal(payload, &message); err != nil {
		return ""
	}

	switch {
	case message.Type == "resize":
		if message.Columns <= 0 || message.Rows <= 0 {
			return ""
		}
		if message.Columns > maxTerminalDimension || message.Rows > maxTerminalDimension {
			return ""
		}
		return "resize"
	case message.Type == "client" && message.Status == "disconnected":
		return "client_disconnected"
	}

	return ""
}

func localShellSocketPath() string {
	return os.Getenv("TUIST_RUNNER_SHELL_SOCKET")
}

func serveLocalShellSocket(socketPath string) error {
	if socketPath == "" {
		return errors.New("TUIST_RUNNER_SHELL_SOCKET is required in PTY server mode")
	}

	if err := os.MkdirAll(filepath.Dir(socketPath), 0o700); err != nil {
		return err
	}
	_ = os.Remove(socketPath)

	listener, err := net.Listen("unix", socketPath)
	if err != nil {
		return err
	}
	defer listener.Close()
	defer os.Remove(socketPath)

	if err := os.Chmod(socketPath, 0o600); err != nil {
		return err
	}

	logf("local shell socket listening at %s", socketPath)

	for {
		conn, err := listener.Accept()
		if err != nil {
			return err
		}

		if err := handleLocalShellConnection(conn); err != nil {
			logf("local shell connection failed: %v", err)
		}
	}
}

func handleLocalShellConnection(conn net.Conn) error {
	defer conn.Close()

	shell, err := spawnShell()
	if err != nil {
		return err
	}
	defer shell.Cleanup()

	inputCh := make(chan localShellFrame, 1)
	ptyCh := make(chan ptyMessage, 1)
	waitCh := make(chan int, 1)

	go readLocalShellFrames(conn, inputCh)
	go readPTY(shell.PTY, ptyCh)
	go func() { waitCh <- commandExitStatus(shell.Command.Wait()) }()

	for {
		select {
		case frame := <-inputCh:
			if frame.Err != nil {
				return nil
			}

			switch frame.Type {
			case localFrameStdin:
				if _, err := shell.PTY.Write(frame.Payload); err != nil {
					return err
				}
			case localFrameResize:
				_ = handleTextFrame(shell.PTY, frame.Payload)
			case localFrameClose:
				return nil
			}

		case message := <-ptyCh:
			if message.Err != nil {
				status := waitForExitStatus(waitCh, 2*time.Second, 0)
				return writeLocalShellExit(conn, status)
			}

			if err := writeLocalShellFrame(conn, localFrameStdout, message.Payload); err != nil {
				return err
			}

		case status := <-waitCh:
			return writeLocalShellExit(conn, status)
		}
	}
}

func writeLocalShellExit(conn net.Conn, status int) error {
	payload, err := json.Marshal(exitFrame{Type: "exit", Status: status})
	if err != nil {
		return err
	}

	return writeLocalShellFrame(conn, localFrameExit, payload)
}

func readLocalShellFrames(conn net.Conn, ch chan<- localShellFrame) {
	for {
		frame, err := readLocalShellFrame(conn)
		if err != nil {
			ch <- localShellFrame{Err: err}
			return
		}
		ch <- frame
	}
}

func readLocalShellFrame(reader io.Reader) (localShellFrame, error) {
	var header [5]byte
	if _, err := io.ReadFull(reader, header[:]); err != nil {
		return localShellFrame{}, err
	}

	length := binary.BigEndian.Uint32(header[1:])
	if length > maxWebSocketMessageBytes {
		return localShellFrame{}, fmt.Errorf("local shell frame too large: %d", length)
	}

	payload := make([]byte, length)
	if length > 0 {
		if _, err := io.ReadFull(reader, payload); err != nil {
			return localShellFrame{}, err
		}
	}

	return localShellFrame{Type: header[0], Payload: payload}, nil
}

func writeLocalShellFrame(writer io.Writer, frameType byte, payload []byte) error {
	if len(payload) > maxWebSocketMessageBytes {
		return fmt.Errorf("local shell frame too large: %d", len(payload))
	}

	var header [5]byte
	header[0] = frameType
	binary.BigEndian.PutUint32(header[1:], uint32(len(payload)))

	if _, err := writer.Write(header[:]); err != nil {
		return err
	}
	if len(payload) == 0 {
		return nil
	}

	_, err := writer.Write(payload)
	return err
}

func commandExitStatus(err error) int {
	if err == nil {
		return 0
	}

	var exitError *exec.ExitError
	if errors.As(err, &exitError) {
		if status, ok := exitError.Sys().(syscall.WaitStatus); ok {
			if status.Exited() {
				return status.ExitStatus()
			}
			if status.Signaled() {
				return 128 + int(status.Signal())
			}
		}
	}

	return 1
}

func waitForExitStatus(ch <-chan int, timeout time.Duration, fallback int) int {
	select {
	case status := <-ch:
		return status
	case <-time.After(timeout):
		return fallback
	}
}

func spawnShell() (*spawnedShell, error) {
	userName := os.Getenv("TUIST_RUNNER_SHELL_USER")
	if userName == "" {
		userName = "runner"
	}

	user, err := lookupShellUser(userName)
	if err != nil {
		return nil, err
	}

	tempDir, err := os.MkdirTemp("", "tuist-runner-shell-")
	if err != nil {
		return nil, err
	}

	cleanup := func() {
		_ = os.RemoveAll(tempDir)
	}

	if os.Geteuid() == 0 {
		if err := chownForUser(tempDir, user); err != nil {
			cleanup()
			return nil, err
		}
	}
	if err := os.Chmod(tempDir, 0o700); err != nil {
		cleanup()
		return nil, err
	}

	shellPath := shellPath(user)
	env := shellEnvironment(os.Environ(), user, shellPath)

	args, env, err := shellArgs(shellPath, tempDir, promptHost(), env, user)
	if err != nil {
		cleanup()
		return nil, err
	}

	command := exec.Command(args[0], args[1:]...)
	command.Env = env
	command.Dir = shellWorkdir(user.Home)

	attrs := &syscall.SysProcAttr{
		Setsid:  true,
		Setctty: true,
		Ctty:    0,
	}

	if os.Geteuid() == 0 {
		if err := enableNoNewPrivileges(); err != nil {
			logf("failed to enable no_new_privs: %v", err)
		}
		attrs.Credential = &syscall.Credential{Uid: user.UID, Gid: user.GID, Groups: user.Groups}
	}

	tty, err := pty.StartWithAttrs(command, nil, attrs)
	if err != nil {
		cleanup()
		return nil, err
	}

	return &spawnedShell{
		Command: command,
		PTY:     tty,
		Cleanup: func() {
			_ = tty.Close()
			if command.Process != nil {
				_ = command.Process.Signal(syscall.SIGTERM)
			}
			cleanup()
		},
	}, nil
}

func lookupShellUser(name string) (shellUser, error) {
	account, err := osuser.Lookup(name)
	if err != nil {
		return shellUser{}, err
	}

	uid, err := parseUint32(account.Uid)
	if err != nil {
		return shellUser{}, fmt.Errorf("invalid uid for %s: %w", name, err)
	}
	uidInt, err := parseInt(account.Uid)
	if err != nil {
		return shellUser{}, fmt.Errorf("invalid uid for %s: %w", name, err)
	}
	gid, err := parseUint32(account.Gid)
	if err != nil {
		return shellUser{}, fmt.Errorf("invalid gid for %s: %w", name, err)
	}
	gidInt, err := parseInt(account.Gid)
	if err != nil {
		return shellUser{}, fmt.Errorf("invalid gid for %s: %w", name, err)
	}

	return shellUser{
		Name:   name,
		UID:    uid,
		GID:    gid,
		UIDInt: uidInt,
		GIDInt: gidInt,
		Groups: supplementaryGroups(account, gid),
		Home:   account.HomeDir,
		Shell:  lookupUserShell(name),
	}, nil
}

func supplementaryGroups(account *osuser.User, primaryGID uint32) []uint32 {
	groups := map[uint32]struct{}{primaryGID: {}}
	groupIDs, err := account.GroupIds()
	if err != nil {
		return []uint32{primaryGID}
	}

	for _, groupID := range groupIDs {
		gid, err := parseUint32(groupID)
		if err != nil {
			continue
		}
		groups[gid] = struct{}{}
	}

	result := make([]uint32, 0, len(groups))
	for gid := range groups {
		result = append(result, gid)
	}
	sort.Slice(result, func(i, j int) bool { return result[i] < result[j] })
	return result
}

func lookupUserShell(name string) string {
	if shell := lookupUserShellFromPasswd(name); shell != "" {
		return shell
	}
	if shell := lookupUserShellFromDirectoryServices(name); shell != "" {
		return shell
	}
	return ""
}

func lookupUserShellFromPasswd(name string) string {
	passwd, err := os.ReadFile("/etc/passwd")
	if err != nil {
		return ""
	}

	for _, line := range strings.Split(string(passwd), "\n") {
		if strings.TrimSpace(line) == "" || strings.HasPrefix(line, "#") {
			continue
		}

		parts := strings.Split(line, ":")
		if len(parts) >= 7 && parts[0] == name {
			return parts[6]
		}
	}

	return ""
}

func lookupUserShellFromDirectoryServices(name string) string {
	if _, err := os.Stat("/usr/bin/dscl"); err != nil {
		return ""
	}

	output, err := exec.Command("/usr/bin/dscl", ".", "-read", "/Users/"+name, "UserShell").Output()
	if err != nil {
		return ""
	}

	fields := strings.Fields(string(output))
	if len(fields) < 2 || fields[0] != "UserShell:" {
		return ""
	}

	return fields[1]
}

func parseUint32(value string) (uint32, error) {
	parsed, err := strconv.ParseUint(value, 10, 32)
	if err != nil {
		return 0, err
	}
	return uint32(parsed), nil
}

func parseInt(value string) (int, error) {
	parsed, err := strconv.Atoi(value)
	if err != nil {
		return 0, err
	}
	if parsed < 0 {
		return 0, fmt.Errorf("value %d is negative", parsed)
	}
	return parsed, nil
}

func chownForUser(path string, user shellUser) error {
	return os.Chown(path, user.UIDInt, user.GIDInt)
}

func shellPath(user shellUser) string {
	candidates := []string{
		os.Getenv("TUIST_RUNNER_SHELL_PATH"),
		user.Shell,
		"/bin/bash",
	}

	for _, candidate := range candidates {
		if candidate == "" {
			continue
		}

		if strings.Contains(candidate, "/") {
			if info, err := os.Stat(candidate); err == nil && !info.IsDir() && info.Mode()&0o111 != 0 {
				return candidate
			}
			continue
		}

		if resolved, err := exec.LookPath(candidate); err == nil {
			return resolved
		}
	}

	return "/bin/bash"
}

func shellEnvironment(base []string, user shellUser, shellPath string) []string {
	env := unsetEnv(base, "TUIST_RUNNER_TOKEN_PATH")
	env = unsetEnv(env, "TUIST_RUNNER_SHELL_DISCOVERY_URL")
	env = setEnv(env, "HOME", user.Home)
	env = setEnv(env, "USER", user.Name)
	env = setEnv(env, "LOGNAME", user.Name)
	env = setEnv(env, "SHELL", shellPath)
	env = setEnvIfMissing(env, "TERM", "xterm-256color")
	env = setEnv(env, "TUIST_RUNNER_INTERACTIVE_SHELL", "1")
	return env
}

func unsetEnv(env []string, key string) []string {
	prefix := key + "="
	filtered := env[:0]
	for _, entry := range env {
		if !strings.HasPrefix(entry, prefix) {
			filtered = append(filtered, entry)
		}
	}
	return filtered
}

func setEnv(env []string, key string, value string) []string {
	prefix := key + "="
	for index, entry := range env {
		if strings.HasPrefix(entry, prefix) {
			env[index] = prefix + value
			return env
		}
	}
	return append(env, prefix+value)
}

func setEnvIfMissing(env []string, key string, value string) []string {
	prefix := key + "="
	for _, entry := range env {
		if strings.HasPrefix(entry, prefix) {
			return env
		}
	}
	return append(env, prefix+value)
}

func shellWorkdir(home string) string {
	candidates := []string{
		os.Getenv("TUIST_RUNNER_SHELL_WORKDIR"),
		"/home/runner/actions-runner/_work",
		"/Users/runner/work",
		home,
	}

	for _, candidate := range candidates {
		if candidate == "" {
			continue
		}
		if info, err := os.Stat(candidate); err == nil && info.IsDir() {
			return candidate
		}
	}

	return "/"
}

func promptHost() string {
	configured := os.Getenv("TUIST_RUNNER_SHELL_PROMPT_HOST")
	source := configured
	if source == "" {
		source = os.Getenv("TUIST_RUNNER_POD_NAME")
	}
	if source == "" {
		if hostname, err := os.Hostname(); err == nil {
			source = hostname
		}
	}

	if configured == "" && strings.Contains(source, "-runner-") {
		parts := strings.Split(source, "-runner-")
		source = parts[len(parts)-1]
	} else if configured == "" {
		parts := strings.Split(source, "-")
		if len(parts) > 1 && len(parts[len(parts)-1]) >= 6 {
			source = parts[len(parts)-1]
		}
	}

	var builder strings.Builder
	for _, char := range source {
		if (char >= 'a' && char <= 'z') || (char >= 'A' && char <= 'Z') ||
			(char >= '0' && char <= '9') || char == '.' || char == '_' || char == '-' {
			builder.WriteRune(char)
		}
	}

	cleaned := builder.String()
	if cleaned == "" {
		cleaned = "runner"
	}
	if len(cleaned) > 24 {
		cleaned = cleaned[:24]
	}
	return cleaned
}

func shellArgs(shellPath string, tempDir string, host string, env []string, user shellUser) ([]string, []string, error) {
	switch filepath.Base(shellPath) {
	case "bash":
		rcPath := filepath.Join(tempDir, "bashrc")
		body := fmt.Sprintf(`
if [ -r /etc/profile ]; then . /etc/profile; fi
if [ -r /etc/bash.bashrc ]; then . /etc/bash.bashrc; fi
if [ -r "$HOME/.bash_profile" ]; then
  . "$HOME/.bash_profile"
elif [ -r "$HOME/.bash_login" ]; then
  . "$HOME/.bash_login"
elif [ -r "$HOME/.profile" ]; then
  . "$HOME/.profile"
fi
if [ -r "$HOME/.bashrc" ]; then . "$HOME/.bashrc"; fi
%s
PROMPT_COMMAND=
PS1='\u@%s $(__tuist_prompt_dir) \$ '
`, promptDirFunctionBody(`printf "%s"`, true), host)
		if err := writeShellStartupFile(rcPath, body, user); err != nil {
			return nil, nil, err
		}
		return []string{shellPath, "--noprofile", "--rcfile", rcPath, "-i"}, env, nil

	case "zsh":
		body := fmt.Sprintf(`
for __tuist_rc in /etc/zprofile "$HOME/.zprofile" /etc/zshrc "$HOME/.zshrc"; do
  if [ -r "$__tuist_rc" ]; then source "$__tuist_rc"; fi
done
unset __tuist_rc
%s
setopt PROMPT_SUBST
PROMPT='%%n@%s $(__tuist_prompt_dir) %%# '
RPROMPT=''
`, promptDirFunctionBody("print -r --", false), host)
		if err := writeShellStartupFile(filepath.Join(tempDir, ".zshrc"), body, user); err != nil {
			return nil, nil, err
		}
		return []string{shellPath, "-i"}, setEnv(env, "ZDOTDIR", tempDir), nil

	default:
		env = setEnv(env, "PS1", fmt.Sprintf(`\u@%s \W \$ `, host))
		env = setEnv(env, "PROMPT", fmt.Sprintf("%%n@%s %%1~ %%# ", host))
		return []string{shellPath, "-i"}, env, nil
	}
}

func promptDirFunctionBody(outputCommand string, escapeTilde bool) string {
	tilde := "~"
	if escapeTilde {
		tilde = `\~`
	}

	return fmt.Sprintf(`
__tuist_prompt_dir() {
  local path="${PWD/#$HOME/%s}"
  path="${path/#%s\/actions-runner\/_work/%s\/work}"
  path="${path/#\/home\/runner\/actions-runner\/_work/%s\/work}"
  path="${path/#\/Users\/runner\/work/%s\/work}"
  %s "$path"
}
`, tilde, tilde, tilde, tilde, tilde, outputCommand)
}

func writeShellStartupFile(path string, body string, user shellUser) error {
	if err := os.WriteFile(path, []byte(body), 0o600); err != nil {
		return err
	}
	if os.Geteuid() == 0 {
		if err := chownForUser(path, user); err != nil {
			return err
		}
	}
	return os.Chmod(path, 0o600)
}
