import os
import re
import json
import time
import subprocess
import sys
import requests
from urllib.parse import urljoin, urlparse
from pathlib import Path
from bs4 import BeautifulSoup
from rich.console import Console
from rich.table import Table
from rich.text import Text
from rich import box
from rich.progress import track

# --- Configuration ---
REPO_OWNER = "ngi-nix"
REPO_NAME = "ngipkgs"
GITHUB_API_URL = f"https://api.github.com/repos/{REPO_OWNER}/{REPO_NAME}/issues"
NLNET_INDEX_URL = "https://nlnet.nl/project/index.html"

# Cache paths
CACHE_DIR = Path("/tmp/ngi_cache")
CACHE_DIR.mkdir(parents=True, exist_ok=True)

HTML_CACHE_FILE = CACHE_DIR / "nlnet-index.html"
DETAILS_CACHE_FILE = CACHE_DIR / "project_details_v2.json"

CACHE_TTL = 86400  # 1 day

# Mapping strictly based on Logo filenames and specific text phrases
# These are the "Source of Truth" markers.
GRANT_MARKERS = {
    "NGI0 Entrust": {
        "logos": ["logo_NGI0_Entrust", "NGI0Entrust"],
        "phrases": ["funded through the NGI0 Entrust Fund"],
        "label": "NGI0 Entrust",
        "nix_attr": "Entrust"
    },
    "NGI0 Core": {
        "logos": ["logo_NGI0_Core", "NGI0Core"],
        "phrases": ["funded through the NGI0 Core Fund"],
        "label": "NGI0 Core",
        "nix_attr": "Core"
    },
    "NGI0 Commons": {
        "logos": ["logo_NGI0CommonsFund", "NGI0Commons"],
        "phrases": ["funded through the NGI0 Commons Fund"],
        "label": "NGI0 Commons",
        "nix_attr": "Commons"
    },
    "NGI0 Review": {
        "logos": ["logo_NGI0_Review", "NGI0Review"],
        "phrases": ["funded through the NGI0 Review Fund"],
        "label": "NGI0 Review",
        "nix_attr": "Review"
    },
    "NGI0 Discovery": {
        "logos": ["logo_NGI0_Discovery"],
        "phrases": ["funded through the NGI0 Discovery Fund"],
        "label": "NGI0 Discovery", # Often mapped to legacy or specific tags
        "nix_attr": "Discovery"
    },
    "NGI0 PET": {
        "logos": ["logo_NGI0_PET"],
        "phrases": ["funded through the NGI0 PET Fund"],
        "label": "NGI0 PET",
        "nix_attr": "PET"
    }
}

PROJECT_ROOT = Path("projects").resolve()
console = Console()

# --- Helpers ---

def get_gh_headers():
    token = os.getenv("GITHUB_TOKEN")
    if not token:
        console.print("[bold red]Error:[/bold red] GITHUB_TOKEN is not set.")
        sys.exit(1)
    return {
        "Authorization": f"token {token}",
        "Accept": "application/vnd.github.v3+json",
    }


def fetch_nlnet_index_html():
    is_fresh = False
    if HTML_CACHE_FILE.exists():
        age = time.time() - HTML_CACHE_FILE.stat().st_mtime
        if age < CACHE_TTL:
            is_fresh = True

    if is_fresh:
        with open(HTML_CACHE_FILE, "r", encoding="utf-8") as f:
            return f.read()

    console.print("[blue]Downloading fresh NLnet index...[/blue]")
    try:
        resp = requests.get(NLNET_INDEX_URL)
        resp.raise_for_status()
        html_content = resp.text
        with open(HTML_CACHE_FILE, "w+", encoding="utf-8") as f:
            f.write(html_content)
        return html_content
    except Exception as e:
        console.print(f"[red]Failed to fetch NLnet index:[/red] {e}")
        if HTML_CACHE_FILE.exists():
            return open(HTML_CACHE_FILE).read()
        return ""


def parse_nlnet_projects(html_content):
    if not html_content:
        return {}
    soup = BeautifulSoup(html_content, "html.parser")
    projects = {}

    ignored_slugs = {
        "index", "current", "completed", "about", "contact", "support",
        "logo", "nix", "press", "search", "submit", "privacy", "planet",
        "open_calls", "guide", "discovery", "news", "people", "events"
    }

    for a in soup.find_all("a", href=True):
        href = a["href"]
        full_url = urljoin(NLNET_INDEX_URL, href)
        if "/project/" not in full_url:
            continue

        path = urlparse(full_url).path.rstrip("/")
        filename = path.split("/")[-1]
        slug = filename.replace(".html", "")

        if not slug or slug.lower() in ignored_slugs:
            continue

        name = a.get_text().strip()
        if not name:
            continue

        projects[name.lower()] = full_url
        projects[slug.lower()] = full_url
        projects[name.lower().replace(" ", "")] = full_url

    return projects


def identify_grant_type(soup):
    """
    Strictly identifies the grant type based on Logos or Footer declaration.
    Returns exactly ONE grant type (Label, NixAttr) or None.
    """

    # 1. Check for Logos (Most reliable for NLnet)
    # They usually put the funding logo in the sidebar or footer
    images = soup.find_all("img", src=True)
    for img in images:
        src = img['src']
        for grant_name, markers in GRANT_MARKERS.items():
            for logo_marker in markers['logos']:
                if logo_marker in src:
                    return markers['label'], markers['nix_attr']

    # 2. Check for Text Declaration (Fallback)
    # "This project was funded through the NGI0 Core Fund"
    text = soup.get_text()
    for grant_name, markers in GRANT_MARKERS.items():
        for phrase in markers['phrases']:
            if phrase in text:
                return markers['label'], markers['nix_attr']

    return None, None


def get_project_grant_from_nlnet_url(url, details_cache):
    if url in details_cache:
        return details_cache[url]

    try:
        # Rate limit protection
        time.sleep(0.5)
        resp = requests.get(url, timeout=10)
        soup = BeautifulSoup(resp.text, "html.parser")

        # Remove navigation/unrelated content to prevent false text matches
        # (Though our logo check usually bypasses this need)
        for noise in soup.select("div#menu, nav, .menu"):
            noise.decompose()

        label, nix_attr = identify_grant_type(soup)

        result = (label, nix_attr) if label else None
        details_cache[url] = result
        return result

    except Exception as e:
        console.print(f"[red]Error checking {url}:[/red] {e}")
        return None


def load_details_cache():
    if DETAILS_CACHE_FILE.exists():
        try:
            with open(DETAILS_CACHE_FILE, "r") as f:
                return json.load(f)
        except json.JSONDecodeError:
            return {}
    return {}

def save_details_cache(cache):
    with open(DETAILS_CACHE_FILE, "w") as f:
        json.dump(cache, f, indent=2)

def get_all_github_issues():
    all_issues = []
    page = 1
    per_page = 100

    with console.status("[bold green]Fetching GitHub issues...") as status:
        while True:
            try:
                status.update(f"Fetching GitHub issues (Page {page})...")
                resp = requests.get(
                    GITHUB_API_URL,
                    headers=get_gh_headers(),
                    params={"labels": "NGI Project", "state": "open", "per_page": per_page, "page": page},
                )
                resp.raise_for_status()
                data = resp.json()
                if not data: break
                all_issues.extend(data)
                page += 1
            except Exception as e:
                console.print(f"[red]GitHub API Error:[/red] {e}")
                sys.exit(1)
    return all_issues

def get_subgrants():
    # Only pull metadata.subgrants to be fast and safe
    nix_expr = """
    let
      pkgs = import <nixpkgs> {};
      projects = (import ./default.nix {}).hydrated-projects;
    in
      pkgs.lib.mapAttrs (n: v: v.metadata.subgrants) projects
    """
    cmd = ["nix", "eval", "--json", "--impure", "--expr", nix_expr]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        return None
    return json.loads(result.stdout)

# --- Main ---

def main():
    if not PROJECT_ROOT.exists():
        console.print(f"[bold red]Error:[/bold red] Cannot find projects dir at {PROJECT_ROOT}")
        sys.exit(1)

    html_content = fetch_nlnet_index_html()
    nlnet_projects_map = parse_nlnet_projects(html_content)
    details_cache = load_details_cache()
    issues = get_all_github_issues()
    subgrants_data = get_subgrants()

    table = Table(box=box.ROUNDED, expand=True, show_lines=True)
    table.add_column("Project", style="bold cyan")
    table.add_column("NLnet Sources", style="blue")
    table.add_column("GitHub Labels", style="white")
    table.add_column("Nix Attrs", style="white")

    updates_made = False

    for issue in track(issues, description="Verifying Projects..."):
        # 1. Parse Project Name
        title_match = re.search(r"NGI Project:\s*(.+)", issue["title"], re.IGNORECASE)
        if not title_match: continue
        project_name = title_match.group(1).strip()
        if not project_name: continue

        # 2. Gather URLs (The "Subgrants")
        nlnet_urls = set()
        body = issue.get("body", "") or ""

        # Regex to find links in body
        body_links = re.findall(r"(https?://nlnet\.nl/project/[\w\d\-\_./]+)", body)
        for link in body_links:
            clean_link = link.rstrip(").,")
            if "index.html" not in clean_link:
                nlnet_urls.add(clean_link)

        # If empty, try to guess from index
        if not nlnet_urls:
            guess_url = nlnet_projects_map.get(project_name.lower())
            if not guess_url:
                guess_url = nlnet_projects_map.get(project_name.lower().replace(" ", ""))
            if guess_url:
                nlnet_urls.add(guess_url)

        # 3. Resolve Funds (The Truth)
        # One URL -> Exactly One Fund.
        # Project -> Set of Funds (Union of all URLs)
        true_labels = set()
        true_nix_attrs = set()

        url_status_text = []

        for url in nlnet_urls:
            if url not in details_cache:
                updates_made = True

            res = get_project_grant_from_nlnet_url(url, details_cache)

            if res:
                lbl, attr = res
                true_labels.add(lbl)
                true_nix_attrs.add(attr)
                url_status_text.append(f"{attr}") # e.g. "Core"
            else:
                url_status_text.append("?")

        # 4. Compare GitHub
        gh_labels = {l["name"] for l in issue["labels"]}

        # We only care about NGI0 labels for sync purposes
        relevant_gh_labels = {l for l in gh_labels if "NGI" in l}

        missing_gh = true_labels - relevant_gh_labels
        extra_gh = {l for l in relevant_gh_labels if l not in true_labels and l != "NGI Project"}

        gh_status = Text()
        if not missing_gh and not extra_gh:
            gh_status = Text("✔ Synced", style="green")
        else:
            if missing_gh:
                gh_status.append(f"+ {', '.join(missing_gh)}\n", style="green")
            if extra_gh:
                gh_status.append(f"- {', '.join(extra_gh)}", style="red")

        # 5. Compare Nix
        nix_status = Text()
        if subgrants_data is None:
             nix_status = Text("Skipped", style="dim")
        else:
            nix_project_data = subgrants_data.get(project_name, {})
            if not nix_project_data and project_name not in subgrants_data:
                 nix_status = Text("Missing File", style="red")
            else:
                current_nix_attrs = set()
                if isinstance(nix_project_data, dict):
                    for k, v in nix_project_data.items():
                        if v and len(v) > 0:
                            current_nix_attrs.add(k)

                missing_nix = true_nix_attrs - current_nix_attrs
                extra_nix = current_nix_attrs - true_nix_attrs

                if not missing_nix and not extra_nix:
                    nix_status = Text("✔ Synced", style="green")
                else:
                    if missing_nix:
                        nix_status.append(f"+ {', '.join(missing_nix)}\n", style="green")
                    if extra_nix:
                        nix_status.append(f"- {', '.join(extra_nix)}", style="red")

        # 6. Render
        # Show row if there is ANY desync
        is_desync = ("Synced" not in gh_status.plain) or ("Synced" not in nix_status.plain)

        if is_desync:
            src_str = ", ".join(url_status_text) if url_status_text else "[red]No Links[/red]"
            table.add_row(project_name, src_str, gh_status, nix_status)

    console.print(table)

    if updates_made:
        save_details_cache(details_cache)

if __name__ == "__main__":
    main()
