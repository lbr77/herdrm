// Command herdr-tailcat-bridge is the standalone CLI form of the tailcat
// client transport. The app uses the same code in-process via the gomobile
// xcframework (Packages/HerdrTailcat); this binary exists for headless use and
// debugging — it serves a remote herdr's socket on a local Unix socket so a
// plain `herdr` CLI (HERDR_SOCKET_PATH=...) can attach and drive it.
//
// All logic lives in the shared bridge package; this is only flag parsing and
// signal handling. The token is read from -token, or from HERDR_TAILCAT_TOKEN
// when -token is empty, so the secret need not appear in the process list.
package main

import (
	"flag"
	"log"
	"os"
	"os/signal"
	"syscall"

	"github.com/missuo/herdrm/tailcat/bridge"
)

func main() {
	log.SetPrefix("[herdr-tailcat-bridge] ")
	log.SetFlags(log.LstdFlags | log.Lmsgprefix)

	var token, listen string
	var port, clientPort uint
	flag.StringVar(&token, "token", "", "tailcat connection token (or HERDR_TAILCAT_TOKEN)")
	flag.StringVar(&listen, "listen", "", "local Unix socket path for the herdr API socket")
	flag.UintVar(&port, "port", bridge.DefaultControlPort, "tunnel TCP port the herdr API socket is served on")
	flag.UintVar(&clientPort, "client-port", bridge.DefaultClientPort, "tunnel TCP port the herdr client socket is served on")
	flag.Parse()
	// The shared package serves the fixed plugin ports; the flags are kept for
	// CLI compatibility but the plugin's contract (6464/6465) is what runs.
	_ = port
	_ = clientPort

	if token == "" {
		token = os.Getenv("HERDR_TAILCAT_TOKEN")
	}
	if token == "" || listen == "" {
		log.Fatal("both -token (or HERDR_TAILCAT_TOKEN) and -listen are required")
	}

	b, err := bridge.Start(token, listen)
	if err != nil {
		log.Fatalf("start bridge: %v", err)
	}
	log.Printf("listening: api %s, client %s", listen, bridge.DeriveClientSocket(listen))

	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
	<-sig
	b.Close()
	bridge.Stop(listen)
}
