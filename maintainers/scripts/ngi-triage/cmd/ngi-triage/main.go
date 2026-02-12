package main

import (
	"flag"
	"ngi-triage/pkg/tui"
)

func main() {
	force := flag.Bool("force", false, "Force re-scrape of NLnet")
	flag.Parse()
	tui.Start(*force)
}
