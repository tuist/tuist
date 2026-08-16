package main

import (
	"fmt"
	"net"
	"os"
)

func main() {
	host := os.Args[1]
	ips, err := net.LookupHost(host)
	if err != nil {
		fmt.Printf("FAIL %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("OK %v\n", ips)
}
