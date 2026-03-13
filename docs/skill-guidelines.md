# Agent Skills Guidelines

Guidelines for creating and maintaining agent skills in the `forjd` organisation.

## What is a skill?

A skill is a folder containing a `SKILL.md` file with YAML frontmatter and Markdown instructions. Skills give agents procedural knowledge and context they can load on demand.

All skills live in the `skills/` directory at the repo root:

```
skills/
├── my-skill/
│   ├── SKILL.md          # Required: metadata + instructions
│   ├── scripts/          # Optional: executable code
│   ├── references/       # Optional: additional documentation
│   └── assets/           # Optional: templates, resources
└── another-skill/
    └── SKILL.md
```

## SKILL.md format

Every skill must have a `SKILL.md` with YAML frontmatter:

```markdown
---
name: my-skill
description: >
  What this skill does and when to use it. Be specific about triggers.
---

# My Skill

Instructions go here...
```

### Required fields

| Field         | Constraints                                                                           |
|---------------|---------------------------------------------------------------------------------------|
| `name`        | Max 64 chars. Lowercase letters, numbers, hyphens only. Must match the directory name.|
| `description` | Max 1024 chars. Describes what the skill does and when to use it.                     |

### Optional fields

| Field           | Purpose                                                        |
|-----------------|----------------------------------------------------------------|
| `license`       | Licence name or reference to a bundled licence file.           |
| `compatibility` | Environment requirements (tools, network access, etc.).        |
| `metadata`      | Arbitrary key-value pairs (author, version, etc.).             |
| `allowed-tools` | Space-delimited list of pre-approved tools. (Experimental)     |

### Name rules

- Lowercase alphanumeric and hyphens only
- No leading, trailing, or consecutive hyphens
- Must match the parent directory name

### Description guidelines

- **Use imperative phrasing**: "Use this skill when..." not "This skill does..."
- **Focus on user intent**: describe what the user is trying to achieve
- **Be specific about triggers**: list contexts where the skill applies, including non-obvious ones
- **Include keywords** that help agents identify relevant tasks

```yaml
# Bad
description: Helps with deployments.

# Good
description: >
  Deploy services to our staging and production environments using
  our internal CLI. Use when the user wants to deploy, rollback,
  or check deployment status, even if they just say "ship it" or
  "push to prod."
```

## Progressive disclosure

Skills use a three-tier loading strategy to manage context efficiently:

1. **Discovery** (~100 tokens): Only `name` and `description` are loaded at startup
2. **Activation** (< 5000 tokens recommended): Full `SKILL.md` body loads when the skill matches a task
3. **Resources** (as needed): Referenced files load only when required

Keep `SKILL.md` under 500 lines. Move detailed reference material to separate files.

## Writing effective instructions

### Add what the agent lacks, omit what it knows

Focus on project-specific conventions, domain procedures, non-obvious edge cases, and specific tools/APIs. Don't explain general concepts the agent already understands.

```markdown
<!-- Too verbose -->
## Extract PDF text
PDF (Portable Document Format) files are a common file format...

<!-- Better -->
## Extract PDF text
Use pdfplumber for text extraction. For scanned documents, fall back to
pdf2image with pytesseract.
```

### Provide defaults, not menus

Pick a recommended approach and mention alternatives briefly:

```markdown
<!-- Too many options -->
You can use pypdf, pdfplumber, PyMuPDF, or pdf2image...

<!-- Better -->
Use pdfplumber for text extraction. For scanned PDFs requiring OCR,
use pdf2image with pytesseract instead.
```

### Favour procedures over declarations

Teach the agent *how to approach* a class of problems, not *what to produce* for a specific instance.

### Match specificity to fragility

- **Give freedom** when multiple approaches are valid
- **Be prescriptive** when operations are fragile or order matters

## Useful patterns

### Templates for output format

Provide concrete templates rather than prose descriptions of formats:

````markdown
## Report structure

```markdown
# [Analysis Title]

## Executive summary
[One-paragraph overview]

## Key findings
- Finding 1 with supporting data

## Recommendations
1. Specific actionable recommendation
```
````

### Checklists for multi-step workflows

```markdown
## Deployment workflow

- [ ] Step 1: Run pre-flight checks
- [ ] Step 2: Create backup
- [ ] Step 3: Deploy to staging
- [ ] Step 4: Run smoke tests
- [ ] Step 5: Promote to production
```

### Validation loops

Instruct the agent to validate its own work before moving on:

```markdown
1. Make your changes
2. Run validation: `python scripts/validate.py output/`
3. If validation fails, fix issues and re-run
4. Only proceed when validation passes
```

### Plan-validate-execute

For batch or destructive operations, have the agent create an intermediate plan, validate it, then execute.

## Bundling scripts

### When to bundle

If you notice the agent reinventing the same logic across runs, write a tested script and bundle it in `scripts/`.

### Script design rules

1. **No interactive prompts** — agents cannot respond to TTY input; accept all input via flags, env vars, or stdin
2. **Include `--help`** — this is how the agent learns the interface
3. **Write helpful error messages** — say what went wrong, what was expected, and what to try
4. **Use structured output** — prefer JSON/CSV over free-form text; send data to stdout, diagnostics to stderr
5. **Be idempotent** — agents may retry; "create if not exists" is safer than "create and fail on duplicate"
6. **Support `--dry-run`** for destructive operations

### Self-contained dependencies

Use inline dependency declarations so scripts need no separate install step:

```python
# /// script
# dependencies = [
#   "beautifulsoup4>=4.12,<5",
# ]
# ///

from bs4 import BeautifulSoup
# ...
```

Run with `uv run scripts/extract.py`.

### Reference scripts from SKILL.md

Use relative paths from the skill directory root:

````markdown
## Available scripts

- **`scripts/validate.sh`** — Validates configuration files

## Workflow

1. Run validation:
   ```bash
   bash scripts/validate.sh "$INPUT_FILE"
   ```
````

## File references

- Use relative paths from the skill root
- Keep references one level deep from `SKILL.md`
- Avoid deeply nested reference chains

## Quality checklist

Before merging a new skill:

- [ ] `name` follows naming rules and matches directory name
- [ ] `description` is specific, imperative, and under 1024 chars
- [ ] `SKILL.md` body is under 500 lines
- [ ] Instructions focus on what the agent wouldn't know without the skill
- [ ] Scripts are non-interactive and include `--help`
- [ ] Tested against realistic prompts (does it trigger when it should? does it not trigger when it shouldn't?)
- [ ] Reference files are focused and loaded on demand, not all at once
