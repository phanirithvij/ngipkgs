package tui

import (
	"fmt"
	"io"
	"ngi-triage/pkg/audit"
	"ngi-triage/pkg/scraper"
	"os"
	"os/exec"
	"strings"

	"github.com/charmbracelet/bubbles/key"
	"github.com/charmbracelet/bubbles/list"
	"github.com/charmbracelet/bubbles/spinner"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

var (
	docStyle     = lipgloss.NewStyle().Margin(1, 2)
	statusGreen  = lipgloss.NewStyle().Foreground(lipgloss.Color("42"))
	statusRed    = lipgloss.NewStyle().Foreground(lipgloss.Color("196"))
	statusYellow = lipgloss.NewStyle().Foreground(lipgloss.Color("220"))
	titleStyle   = lipgloss.NewStyle().Foreground(lipgloss.Color("205")).Bold(true)
)

type model struct {
	list         list.Model
	viewport     viewport.Model
	spinner      spinner.Model
	loading      bool
	nlnetDB      map[string]scraper.ProjectData
	ready        bool
	forceScrape  bool
	forceRefresh bool
	err          error
}

// Init triggers the initial data load
func (m model) Init() tea.Cmd {
	return tea.Batch(m.spinner.Tick, loadDataCmd(m.forceScrape, m.forceRefresh))
}

// --- Messages ---
type dataLoadedMsg struct {
	items []list.Item
	db    map[string]scraper.ProjectData
}

type statusMsg struct {
	msg string // For showing temp status in footer if needed
}

// --- COMMANDS ---

func loadDataCmd(forceScrape bool, forceRefresh bool) tea.Cmd {
	return func() tea.Msg {
		// 1. Load Scraper DB (Instant if cached)
		db, err := scraper.LoadOrScrape(forceScrape)
		if err != nil {
			return nil
		}

		// 2. Run Audit (Instant if cached, unless forceRefresh is true)
		results, err := audit.RunAudit(db, forceRefresh)
		if err != nil {
			return nil
		}

		items := make([]list.Item, len(results))
		for i, r := range results {
			items[i] = r
		}
		return dataLoadedMsg{items: items, db: db}
	}
}

// --- SAFE COMMANDS ---

// 1. Fix Labels (GitHub) - STRICTLY SINGLE ITEM
func fixLabelsCmd(p audit.ProjectStatus) tea.Cmd {
	return func() tea.Msg {
		// Safety Check: Never run on invalid issue numbers
		if p.IssueNumber <= 0 {
			return nil
		}

		// We execute strictly ONE github command per keypress.
		if len(p.MissingLabels) > 0 {
			// e.g. gh issue edit 123 --add-label "NGI0 Core"
			exec.Command("gh", "issue", "edit", fmt.Sprintf("%d", p.IssueNumber), "--add-label", strings.Join(p.MissingLabels, ",")).Run()
		}
		if len(p.ExtraLabels) > 0 {
			exec.Command("gh", "issue", "edit", fmt.Sprintf("%d", p.IssueNumber), "--remove-label", strings.Join(p.ExtraLabels, ",")).Run()
		}

		// Refresh data to show green status
		return loadDataCmd(false, false)()
	}
}

// 2. Intelligent & PARANOID Nix Fixer
func fixNixCmd(p audit.ProjectStatus, db map[string]scraper.ProjectData) tea.Cmd {
	return func() tea.Msg {
		// Safety Check: Path Traversal / Empty Name
		if p.Name == "" || strings.Contains(p.Name, "..") || strings.HasPrefix(p.Name, "/") {
			return nil // Abort: Project name looks dangerous
		}

		// Calculate what needs to be added
		fundToAttr := map[string]string{
			"NGI0 Core":    "Core",
			"NGI0 Entrust": "Entrust",
			"NGI0 Commons": "Commons",

			// Everything else maps to Review
			"NGI0 Review":    "Review",
			"NGI0 PET":       "Review", // Just in case scraper finds old tag
			"NGI0 Discovery": "Review", // Just in case
		}

		type change struct {
			Attr string
			Name string
		}
		var changes []change

		// Only look for grants that we have confirmed via scraping
		for _, u := range p.CleanURLs {
			data, exists := db[u]
			if !exists {
				continue
			}
			if attr, ok := fundToAttr[data.Fund]; ok {
				changes = append(changes, change{Attr: attr, Name: data.Name})
			}
		}

		if len(changes) == 0 {
			return nil
		}

		// Locate File
		path := fmt.Sprintf("projects/%s/default.nix", p.Name)

		// Safety Check: Verify file exists before touching it
		info, err := os.Stat(path)
		if os.IsNotExist(err) || info.IsDir() {
			return nil // Abort: File missing or is a directory
		}

		// Read File
		contentBytes, err := os.ReadFile(path)
		if err != nil {
			return nil
		}
		content := string(contentBytes)

		// Safety Check: Don't edit empty files
		if len(content) < 10 {
			return nil
		}

		dirty := false

		for _, c := range changes {
			// 1. Check if the specific slug (e.g. "Servo-CSS") is already there
			if strings.Contains(content, fmt.Sprintf("%q", c.Name)) {
				continue
			}

			// 2. Try to find the specific list: `Core = [`
			// We look for "Attr = [" to be safe.
			targetHeader := fmt.Sprintf("%s = [", c.Attr)

			if strings.Contains(content, targetHeader) {
				// SAFE INJECTION: Insert immediately after the opening bracket
				// This preserves the list validity.
				replacement := fmt.Sprintf("%s\n        \"%s\"", targetHeader, c.Name)
				content = strings.Replace(content, targetHeader, replacement, 1)
				dirty = true
			} else {
				// 3. If list missing, look for `subgrants = {`
				if strings.Contains(content, "subgrants = {") {
					// SAFE INJECTION: Insert the whole block after subgrants opening
					replacement := fmt.Sprintf("subgrants = {\n      %s = [\n        \"%s\"\n      ];", c.Attr, c.Name)
					content = strings.Replace(content, "subgrants = {", replacement, 1)
					dirty = true
				} else {
					// ABORT: Structure is too complex/unknown.
					// Do NOT try to guess where metadata is.
					// Do NOT use regex to insert at random places.
					// Let the user edit manually.
					continue
				}
			}
		}

		if !dirty {
			return nil
		}

		// Write Back - Only if we actually made safe changes
		if err := os.WriteFile(path, []byte(content), 0644); err != nil {
			return nil // Failed to write
		}

		// formatting is safe, it just fixes indentation
		exec.Command("nixfmt", path).Run()

		return loadDataCmd(false, false)()
	}
}

func openEditorCmd(name string) tea.Cmd {
	return func() tea.Msg {
		editor := os.Getenv("EDITOR")
		if editor == "" {
			editor = "vim"
		}
		path := fmt.Sprintf("projects/%s/default.nix", name)
		if _, err := os.Stat(path); os.IsNotExist(err) {
			path = fmt.Sprintf("projects/%s", name)
		}
		c := exec.Command(editor, path)
		c.Stdin = os.Stdin
		c.Stdout = os.Stdout
		c.Stderr = os.Stderr
		return tea.ExecProcess(c, func(err error) tea.Msg {
			return loadDataCmd(false, false)()
		})
	}
}

// ... [Update Loop] ...

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmds []tea.Cmd
	var cmd tea.Cmd

	switch msg := msg.(type) {
	case tea.KeyMsg:
		if m.list.FilterState() == list.Filtering {
			m.list, cmd = m.list.Update(msg)
			return m, cmd
		}

		switch msg.String() {
		case "ctrl+c", "q":
			return m, tea.Quit
		case "r":
			// Soft Refresh: Updates GitHub Labels & Nix State
			m.loading = true
			cmds = append(cmds, loadDataCmd(false, true))
		case "R":
			// Hard Refresh: Re-scrapes NLnet website AND GitHub
			m.loading = true
			cmds = append(cmds, loadDataCmd(true, true))
		case "o": // GitHub
			if i, ok := m.list.SelectedItem().(audit.ProjectStatus); ok {
				return m, func() tea.Msg { exec.Command("xdg-open", i.IssueURL).Start(); return nil }
			}
		case "n": // NLnet
			if i, ok := m.list.SelectedItem().(audit.ProjectStatus); ok {
				if len(i.CleanURLs) > 0 {
					return m, func() tea.Msg { exec.Command("xdg-open", i.CleanURLs[0]).Start(); return nil }
				}
			}
		case "l": // Fix Labels
			if i, ok := m.list.SelectedItem().(audit.ProjectStatus); ok {
				m.loading = true
				cmds = append(cmds, fixLabelsCmd(i))
			}
		case "f": // Fix Nix (Auto)
			if i, ok := m.list.SelectedItem().(audit.ProjectStatus); ok {
				m.loading = true
				cmds = append(cmds, fixNixCmd(i, m.nlnetDB))
			}
		case "e": // Fix Nix (Manual)
			if i, ok := m.list.SelectedItem().(audit.ProjectStatus); ok {
				return m, openEditorCmd(i.Name)
			}
		}

	// ... [Rest of Update loop] ...
	case tea.WindowSizeMsg:
		h, v := docStyle.GetFrameSize()
		m.list.SetSize(msg.Width-h, msg.Height-v)
		m.viewport.Width = msg.Width / 2
		m.viewport.Height = msg.Height - 5
		m.ready = true

	case dataLoadedMsg:
		m.loading = false
		m.nlnetDB = msg.db
		m.list.SetItems(msg.items)

	case spinner.TickMsg:
		m.spinner, cmd = m.spinner.Update(msg)
		cmds = append(cmds, cmd)
	}

	m.list, cmd = m.list.Update(msg)
	cmds = append(cmds, cmd)

	if m.ready {
		if i, ok := m.list.SelectedItem().(audit.ProjectStatus); ok {
			m.viewport.SetContent(renderAuditView(i))
		}
	}
	return m, tea.Batch(cmds...)
}

func renderAuditView(p audit.ProjectStatus) string {
	s := titleStyle.Render(fmt.Sprintf("%s (#%d)", p.Name, p.IssueNumber)) + "\n\n"

	s += "🔗 NLnet Sources:\n"
	for _, u := range p.CleanURLs {
		s += fmt.Sprintf("  • %s\n", u)
	}
	s += "\n"

	s += "🛠  Action Plan:\n"
	if p.IsSynced {
		s += statusGreen.Render("  ✔  Project is in sync!")
	} else {
		if len(p.CleanURLs) == 0 {
			s += statusYellow.Render("  ⚠️  WARNING: No NLnet URLs found in issue body.\n")
			s += statusYellow.Render("      The tool cannot verify funding sources.\n")
			s += statusYellow.Render("      Suggestions below might be aggressive.\n\n")
		}

		if len(p.MissingLabels) > 0 {
			s += statusGreen.Render(fmt.Sprintf("  [l] Add Labels: %s\n", strings.Join(p.MissingLabels, ", ")))
		}
		if len(p.ExtraLabels) > 0 {
			s += statusRed.Render(fmt.Sprintf("  [l] Remove Labels: %s\n", strings.Join(p.ExtraLabels, ", ")))
		}
		if p.NixStatus == "MISSING" {
			s += statusYellow.Render(fmt.Sprintf("  [!] Create File: projects/%s/default.nix", p.Name))
		}
	}
	return s
}

// --- View ---
func (m model) View() string {
	if m.loading {
		return fmt.Sprintf("\n\n   %s Loading data... please wait.\n\n", m.spinner.View())
	}
	if !m.ready {
		return "Initializing..."
	}

	// Split View: Left List | Right Viewport
	listView := m.list.View()
	detailView := m.viewport.View()

	return lipgloss.JoinHorizontal(lipgloss.Top, listView, "   ", detailView)
}

// --- Delegate for List Customization ---
type itemDelegate struct{}

func (d itemDelegate) Height() int                             { return 1 }
func (d itemDelegate) Spacing() int                            { return 0 }
func (d itemDelegate) Update(_ tea.Msg, _ *list.Model) tea.Cmd { return nil }
func (d itemDelegate) Render(w io.Writer, m list.Model, index int, listItem list.Item) {
	i, ok := listItem.(audit.ProjectStatus)
	if !ok {
		return
	}

	str := fmt.Sprintf("%d. %s", index+1, i.Name)

	icon := "🟢"
	if !i.IsSynced {
		if i.NixStatus == "MISSING" {
			icon = "🟡"
		} else {
			icon = "🔴"
		}
	}

	fn := lipgloss.NewStyle().Foreground(lipgloss.Color("252")).Render
	if index == m.Index() {
		fn = func(s ...string) string {
			return lipgloss.NewStyle().Foreground(lipgloss.Color("205")).Bold(true).Render("> " + strings.Join(s, " "))
		}
	}

	fmt.Fprint(w, fn(fmt.Sprintf("%s %s", icon, str)))
}

func Start(forceScrape bool) {
	s := spinner.New()
	s.Spinner = spinner.Dot
	s.Style = lipgloss.NewStyle().Foreground(lipgloss.Color("205"))

	l := list.New([]list.Item{}, itemDelegate{}, 40, 20)
	l.Title = "NGI Projects Triage"
	l.SetShowHelp(true)
	l.SetFilteringEnabled(true)
	// Add keybindings to list helper
	l.AdditionalFullHelpKeys = func() []key.Binding {
		return []key.Binding{
			key.NewBinding(key.WithKeys("l"), key.WithHelp("l", "fix labels")),
			key.NewBinding(key.WithKeys("e"), key.WithHelp("e", "edit nix")),
			key.NewBinding(key.WithKeys("o"), key.WithHelp("o", "open github")),
			key.NewBinding(key.WithKeys("n"), key.WithHelp("n", "open nlnet")),
			key.NewBinding(key.WithKeys("r"), key.WithHelp("r", "refresh GH/Nix")),
			key.NewBinding(key.WithKeys("R"), key.WithHelp("R", "full rescrape")),
		}
	}

	m := model{
		list:        l,
		viewport:    viewport.New(0, 0),
		spinner:     s,
		loading:     true,
		forceScrape: forceScrape,
	}

	if _, err := tea.NewProgram(m, tea.WithAltScreen()).Run(); err != nil {
		fmt.Println("Error running program:", err)
		os.Exit(1)
	}
}
