package scraper

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"regexp"
	"strings"
	"sync"
	"time"
)

const (
	IndexURL   = "https://nlnet.nl/project/index.html"
	WorkerPool = 50
	CacheFile  = "/tmp/ngi_nlnet_db.json"
)

type ProjectData struct {
	URL  string `json:"url"`
	Name string `json:"name"`
	Fund string `json:"fund"`
}

// STRICT MATCHERS for the big three.
var fundMatchers = map[string]*regexp.Regexp{
	"NGI0 Entrust": regexp.MustCompile(`(?i)(NGI0_tag_Entrust|NGI0_Entrust|funded through.*?NGI0 Entrust)`),
	"NGI0 Core":    regexp.MustCompile(`(?i)(NGI0_tag_Core|NGI0_Core|funded through.*?NGI0 Core)`),
	"NGI0 Commons": regexp.MustCompile(`(?i)(NGI0_tag_Commons|NGI0_Commons|funded through.*?NGI0 Commons)`),
}

var ignoredSlugs = map[string]bool{
	"index": true, "current": true, "completed": true, "about": true,
	"contact": true, "support": true, "logo": true, "nix": true,
	"press": true, "search": true, "submit": true, "privacy": true,
	"planet": true, "open_calls": true, "guide": true, "discovery": true,
	"news": true, "people": true, "events": true, "default": true,
	"index.html": true,
}
var hrefRegex = regexp.MustCompile(`href="([^"]+)"`)

func LoadOrScrape(force bool) (map[string]ProjectData, error) {
	if !force {
		if _, err := os.Stat(CacheFile); err == nil {
			file, err := os.Open(CacheFile)
			if err == nil {
				defer file.Close()
				var data map[string]ProjectData
				if err := json.NewDecoder(file).Decode(&data); err == nil {
					return data, nil
				}
			}
		}
	}
	return runScraper()
}

func runScraper() (map[string]ProjectData, error) {
	fmt.Println("⚡ Fetching NLnet index...")
	resp, err := http.Get(IndexURL)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	bodyBytes, _ := io.ReadAll(resp.Body)
	indexHTML := string(bodyBytes)

	projects := make(map[string]string)
	matches := hrefRegex.FindAllStringSubmatch(indexHTML, -1)
	baseUrl, _ := url.Parse(IndexURL)

	for _, m := range matches {
		ref := m[1]
		absUrl, err := baseUrl.Parse(ref)
		if err != nil {
			continue
		}
		urlString := absUrl.String()

		if !strings.Contains(urlString, "/project/") {
			continue
		}

		path := absUrl.Path
		segments := strings.Split(strings.Trim(path, "/"), "/")
		if len(segments) == 0 {
			continue
		}

		filename := segments[len(segments)-1]
		slug := strings.ReplaceAll(filename, ".html", "")
		slug = strings.ToLower(slug)

		if ignoredSlugs[slug] || slug == "" {
			continue
		}

		cleanUrl := strings.TrimRight(urlString, "/")
		projects[cleanUrl] = slug
	}

	fmt.Printf("⚡ Scraping %d projects (Workers: %d)...\n", len(projects), WorkerPool)

	jobs := make(chan string, len(projects))
	results := make(chan ProjectData, len(projects))
	var wg sync.WaitGroup

	for i := 0; i < WorkerPool; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for url := range jobs {
				results <- scrapePage(url, projects[url])
			}
		}()
	}

	for url := range projects {
		jobs <- url
	}
	close(jobs)
	wg.Wait()
	close(results)

	finalMap := make(map[string]ProjectData)
	for res := range results {
		key := strings.ToLower(strings.TrimRight(res.URL, "/"))
		finalMap[key] = res
	}

	file, _ := os.Create(CacheFile)
	enc := json.NewEncoder(file)
	enc.SetIndent("", "  ")
	enc.Encode(finalMap)
	file.Close()

	return finalMap, nil
}

func scrapePage(pUrl, name string) ProjectData {
	client := http.Client{Timeout: 5 * time.Second}
	resp, err := client.Get(pUrl)
	if err != nil {
		// If we can't fetch it, we can't determine it. Default to Error or Review?
		// Let's keep it as Error so we don't accidentally label broken links.
		return ProjectData{URL: pUrl, Name: name, Fund: "Error"}
	}
	defer resp.Body.Close()
	bytes, _ := io.ReadAll(resp.Body)
	html := string(bytes)

	detectedFund := "NGI0 Review"

	// Try to find a MORE SPECIFIC one (Core, Entrust, Commons)
	for fund, re := range fundMatchers {
		if re.MatchString(html) {
			detectedFund = fund
			break
		}
	}

	// Safety: If it was a valid page but had NO markers, it stays "NGI0 Review".
	// This covers PET, Discovery, and legacy funds.

	return ProjectData{URL: pUrl, Name: name, Fund: detectedFund}
}
