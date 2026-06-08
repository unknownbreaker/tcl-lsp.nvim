// Command tcl-lsp is a Language Server Protocol server for TCL/RVT. It speaks
// LSP over stdio; logs go to stderr (stdout is the protocol channel).
package main

import (
	"log"
	"os"

	"github.com/unknownbreaker/tcl-lsp/internal/lsp"
)

func main() {
	log.SetOutput(os.Stderr)
	log.SetPrefix("tcl-lsp: ")
	srv := lsp.NewServer(lsp.NewConn(os.Stdin, os.Stdout))
	if err := srv.Run(); err != nil {
		log.Fatalf("server error: %v", err)
	}
}
