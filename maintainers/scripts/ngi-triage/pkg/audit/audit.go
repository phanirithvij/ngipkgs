package audit

import (
	"encoding/json"
	"fmt"
	"ngi-triage/pkg/scraper"
	"os"
	"os/exec"
	"regexp"
	"strings"
	"time"
)

const (
	GHCachenFile  = "/tmp/ngi_gh_cache.json"
	NixCacheFile  = "/tmp/ngi_nix_cache.json"
	CacheDuration = 1 * time.Hour // Auto-refresh after 1 hour, or use 'r'
)

type Issue struct {
	Number int     `json:"number"`
	Title  string  `json:"title"`
	Body   string  `json:"body"`
	Labels []Label `json:"labels"`
	URL    string  `json:"url"`
}
type Label struct{ Name string }

type ProjectStatus struct {
	Name          string
	IssueNumber   int
	IssueURL      string
	CleanURLs     []string
	MissingLabels []string
	ExtraLabels   []string
	NixStatus     string
	IsSynced      bool
}

// Helper to save/load JSON cache
func loadCache(path string, v interface{}) bool {
	info, err := os.Stat(path)
	if err != nil || time.Since(info.ModTime()) > CacheDuration {
		return false // Cache missing or stale
	}
	file, err := os.Open(path)
	if err != nil {
		return false
	}
	defer file.Close()
	return json.NewDecoder(file).Decode(v) == nil
}

func saveCache(path string, v interface{}) {
	file, _ := os.Create(path)
	defer file.Close()
	json.NewEncoder(file).Encode(v)
}

// Helper for BubbleTea: Implements list.Item interface
func (p ProjectStatus) Title() string { return p.Name }
func (p ProjectStatus) Description() string {
	if p.IsSynced {
		return "Synced"
	}
	return fmt.Sprintf("Missing: %d | Extra: %d | Nix: %s", len(p.MissingLabels), len(p.ExtraLabels), p.NixStatus)
}
func (p ProjectStatus) FilterValue() string { return p.Name }

// Helper: robust URL normalizer
func normalizeURL(u string) string {
	u = strings.TrimSpace(u)
	u = strings.TrimSuffix(u, ").,") // Clean punctuation
	u = strings.TrimSuffix(u, "/")   // Remove trailing slash
	u = strings.ToLower(u)           // Ignore case
	// Ensure we are matching the 'key' format from scraper
	// Scraper keys are usually full URLs.
	return u
}

// RunAudit now accepts a 'forceRefresh' flag
func RunAudit(nlnetDB map[string]scraper.ProjectData, forceRefresh bool) ([]ProjectStatus, error) {
	var issues []Issue
	var nixData map[string]interface{}

	// 1. Fetch GitHub Issues (Cache or Live)
	if !forceRefresh && loadCache(GHCachenFile, &issues) {
		// Cache hit
	} else {
		// Cache miss or forced
		cmd := exec.Command("gh", "issue", "list", "--repo", "ngi-nix/ngipkgs", "--limit", "2000", "--state", "open", "--json", "number,title,body,labels,url")
		out, err := cmd.Output()
		if err != nil {
			return nil, fmt.Errorf("gh command failed: %v", err)
		}

		if err := json.Unmarshal(out, &issues); err != nil {
			return nil, err
		}
		saveCache(GHCachenFile, issues)
	}

	// 2. Fetch Nix State (Cache or Live)
	if !forceRefresh && loadCache(NixCacheFile, &nixData) {
		// Cache hit
	} else {
		nixExpr := `let pkgs = import <nixpkgs> {}; projects = (import ./default.nix {}).hydrated-projects; in pkgs.lib.mapAttrs (n: v: v.metadata.subgrants) projects`
		cmdNix := exec.Command("nix", "eval", "--json", "--impure", "--expr", nixExpr)
		outNix, _ := cmdNix.Output() // Ignore error as partial success is common

		if err := json.Unmarshal(outNix, &nixData); err != nil {
			// If nix fails completely, utilize empty map but don't crash
			nixData = make(map[string]interface{})
		}
		saveCache(NixCacheFile, nixData)
	}

	// 3. Analyze (Fast, in-memory)
	var results []ProjectStatus
	reTitle := regexp.MustCompile(`(?i)NGI Project:\s*(.+)`)
	reURL := regexp.MustCompile(`(https?://nlnet\.nl/project/[\w\d\-\_./]+)`)

	for _, issue := range issues {
		match := reTitle.FindStringSubmatch(issue.Title)
		if len(match) < 2 {
			continue
		}
		projName := strings.TrimSpace(match[1])

		rawUrls := reURL.FindAllString(issue.Body, -1)
		var cleanUrls []string
		expectedLabels := make(map[string]bool)

		for _, u := range rawUrls {
			clean := normalizeURL(u)
			if strings.Contains(clean, "index.html") {
				continue
			}
			cleanUrls = append(cleanUrls, clean)
			data, ok := nlnetDB[clean]
			if !ok {
				if strings.HasSuffix(clean, "/") {
					data, ok = nlnetDB[strings.TrimSuffix(clean, "/")]
				} else {
					data, ok = nlnetDB[clean+"/"]
				}
			}

			if ok && data.Fund != "Unknown" {
				expectedLabels[data.Fund] = true
			}
		}

		currentLabels := make(map[string]bool)
		for _, l := range issue.Labels {
			currentLabels[l.Name] = true
		}

		var missing []string
		for l := range expectedLabels {
			if !currentLabels[l] {
				missing = append(missing, l)
			}
		}

		var extra []string
		if len(cleanUrls) > 0 {
			for l := range currentLabels {
				if strings.HasPrefix(l, "NGI0 ") && !expectedLabels[l] {
					extra = append(extra, l)
				}
			}
		}
		nixStat := "OK"
		if _, ok := nixData[projName]; !ok {
			nixStat = "MISSING"
		}

		synced := len(missing) == 0 && len(extra) == 0 && nixStat == "OK"

		results = append(results, ProjectStatus{
			Name:          projName,
			IssueNumber:   issue.Number,
			IssueURL:      issue.URL,
			CleanURLs:     cleanUrls,
			MissingLabels: missing,
			ExtraLabels:   extra,
			NixStatus:     nixStat,
			IsSynced:      synced,
		})
	}
	return results, nil
}
