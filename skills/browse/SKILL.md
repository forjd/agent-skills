---
name: browse
description: >
  Browser automation CLI for AI agents. Use when the user needs to interact
  with websites, including navigating pages, filling forms, clicking buttons,
  taking screenshots, extracting data, testing web apps, or automating any
  browser task. Triggers on "browse", "check the page", "take a screenshot",
  "test the UI", "fill the form", "click the button", "QA", "visual check",
  "healthcheck", and any task requiring a real browser.
compatibility: Requires the browse binary. Install with curl -fsSL https://raw.githubusercontent.com/forjd/browse/main/install.sh | bash
---

# Browse — Browser Automation CLI

Fast, lightweight CLI for browser automation. Wraps Playwright behind a persistent daemon for sub-30ms command latency after cold start.

## Setup

Check if `browse` is installed:

```bash
browse version
```

If not installed, offer to install it:

```bash
curl -fsSL https://raw.githubusercontent.com/forjd/browse/main/install.sh | bash
```

## Architecture

```
CLI ──JSON──▶ Unix socket ──▶ Daemon ──▶ Playwright ──▶ Chromium
```

- Single daemon auto-starts on first command, idles out after 30 minutes
- Session persists cookies, localStorage, and auth tokens across commands
- Sub-30ms latency after cold start (~3s)

## Core Interaction Pattern

**Always follow this loop:** snapshot → interact → snapshot again.

```bash
browse goto https://example.com
browse snapshot              # assigns refs: @e1, @e2, @e3...
browse fill @e3 "search"    # interact using refs
browse click @e4
browse snapshot              # re-snapshot after page changes
```

Refs are **ephemeral** — they go stale after any navigation or page mutation. If you get "Refs are stale", run `snapshot` again.

## Command Reference

### Navigation

```bash
browse goto <url>                          # navigate to URL
browse goto <url> --preset mobile          # mobile viewport (also: tablet, desktop)
browse goto <url> --viewport 1280 720      # custom viewport
browse back                                # browser back
browse forward                             # browser forward
browse reload                              # reload (--hard to bypass cache)
browse url                                 # print current URL
```

### Observation

```bash
browse snapshot                            # list interactive elements with refs
browse snapshot -i                         # include structural nodes (headings, text)
browse snapshot -f                         # full accessibility tree
browse screenshot                          # full-page screenshot to stdout path
browse screenshot ./shot.png               # save to specific path
browse screenshot --selector ".modal"      # screenshot specific element
browse text                                # all visible text content
browse console                             # show console logs (errors by default)
browse console --level warning             # filter by level
browse network                             # show failed requests (4xx/5xx)
browse network --all                       # show all requests
```

### Interaction

```bash
browse click @e3                           # click element
browse fill @e2 "hello world"             # type into input (clears first)
browse select @e5 "Option A"              # select dropdown option
browse hover @e1                           # hover element
browse hover @e1 --duration 2000          # hover with hold
browse press Tab                           # keyboard press
browse press Shift+Tab                     # modified key
browse scroll down                         # scroll (down/up/top/bottom)
browse scroll @e7                          # scroll element into view
browse upload @e4 ./file.pdf              # upload file
browse attr @e3                            # read all attributes
browse attr @e3 href                       # read specific attribute
```

### Waiting

```bash
browse wait url "dashboard"                # wait for URL to contain string
browse wait text "Success"                 # wait for text to appear
browse wait visible @e3                    # wait for element visible
browse wait hidden ".spinner"              # wait for element to disappear
browse wait network-idle                   # wait for no pending requests
browse wait 2000                           # fixed delay (ms)
```

All wait commands accept `--timeout <ms>` (default 30s).

### JavaScript

```bash
browse eval "document.title"               # run JS in page context
browse page-eval "await page.title()"      # run Playwright page operations
```

### Tabs

```bash
browse tab list                            # list open tabs
browse tab new https://example.com         # open new tab
browse tab switch 1                        # switch to tab by index
browse tab close                           # close current tab
```

### Authentication

```bash
browse login --env staging                 # configured login (from browse.config.json)
browse auth-state save ./auth.json         # export session (cookies + localStorage)
browse auth-state load ./auth.json         # import session
```

### Assertions (for CI/testing)

```bash
browse assert visible ".submit-btn"        # pass/fail: element visible
browse assert not-visible ".error"         # pass/fail: element hidden
browse assert text-contains "Welcome"      # pass/fail: text on page
browse assert url-contains "/dashboard"    # pass/fail: URL check
browse assert element-count ".item" 5      # pass/fail: element count
```

### Accessibility

```bash
browse a11y                                # WCAG 2.0 AA audit
browse a11y --standard wcag22aa            # WCAG 2.2 AA
browse a11y --json                         # machine-readable output
browse a11y --include ".main-content"      # scope to region
```

### Lifecycle

```bash
browse wipe                                # clear all session data
browse quit                                # shut down daemon
browse healthcheck                         # run configured health checks
```

## Common Workflows

### Form filling

```bash
browse goto https://app.example.com/signup
browse snapshot
# Read refs, then fill and submit
browse fill @e2 "user@example.com"
browse fill @e3 "password123"
browse click @e5
browse wait url "dashboard"
browse screenshot ./after-signup.png
```

### QA testing

```bash
browse goto https://app.example.com
browse screenshot ./homepage.png
browse console --level error               # check for JS errors
browse network                             # check for failed requests
browse a11y --json                         # accessibility audit
browse assert visible ".hero-section"
browse assert text-contains "Welcome"
```

### Responsive testing

```bash
browse goto https://example.com --preset mobile
browse screenshot ./mobile.png
browse goto https://example.com --preset tablet
browse screenshot ./tablet.png
browse goto https://example.com --preset desktop
browse screenshot ./desktop.png
```

### Login then test

```bash
browse login --env staging                 # or manual fill/click flow
browse goto https://app.example.com/settings
browse snapshot
```

## Configuration (optional)

A `browse.config.json` in the project root can define:

- **Environments** — login URLs, credential selectors, success conditions (for `login --env`)
- **Flows** — reusable multi-step workflows (for `flow <name>`)
- **Healthchecks** — multi-page verification with assertions (for `healthcheck`)

## Tips

- **Always snapshot before interacting** — you need refs to click/fill/select
- **Re-snapshot after navigation** — refs go stale when the page changes
- **Use `wait` before asserting** — SPAs need time to render after navigation
- **Check `console` and `network`** after page loads to catch errors early
- **Use `--preset mobile`** on `goto` for responsive testing — don't resize after
- **Use `screenshot`** liberally — it's cheap and helps debug failures
- **Use `wipe`** between unrelated test sessions to clear state
