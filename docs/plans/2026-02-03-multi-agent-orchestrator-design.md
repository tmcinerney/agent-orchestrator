# Multi-Agent Orchestrator Design

**Date:** 2026-02-03
**Status:** Draft - Pending Consensus Review
**Format:** Agent Skills Standard with Optional Claude Plugin Wrapper

## Overview

A CLI-agnostic skill that orchestrates multiple AI agent CLIs (Claude Code, OpenCode, Codex, Gemini CLI, etc.) to perform collaborative tasks such as consensus building, parallel code reviews, test generation, and multi-perspective analysis. Uses tmux for session management and monitoring, with role-based system prompts for specialized agent personas.

## Motivation

Current limitations:
- Single AI agent perspective can miss issues or approaches
- Context window pollution from large exploratory tasks
- No easy way to get consensus across different AI models/providers
- Manual context switching between different CLI tools
- No standard way to orchestrate multiple agents

**Agent Orchestrator solves this by:**
- Enabling any compatible CLI to orchestrate other CLIs
- Providing clean context isolation via tmux sessions
- Supporting role-based personas (planner, codereviewer, consensus, testgen)
- Working across the entire Agent Skills ecosystem (Claude, OpenCode, Codex, Gemini, Cursor, etc.)
- Allowing explicit delegation ("use gemini and codex for consensus") and progressive disclosure (auto-triggering)

## Key Design Decisions

### 1. Agent Skills Standard (Not MCP)

**Decision:** Use the open Agent Skills format (agentskills.io) as the primary implementation.

**Rationale:**
- Works across 25+ compatible CLIs (Claude Code, OpenCode, Codex, Gemini CLI, Cursor, etc.)
- Portable, version-controlled, ecosystem-wide compatibility
- Gemini can orchestrate Claude + Codex, Claude can orchestrate OpenCode + Gemini, etc.
- Not tied to a single vendor or protocol

**Structure:**
```
agent-orchestrator/
├── SKILL.md                    # Agent Skills standard format
├── scripts/
│   ├── orchestrate.sh          # Main orchestration logic
│   ├── spawn-agent.sh          # CLI spawning helper
│   └── monitor-tmux.sh         # Output monitoring
├── references/
│   ├── cli-configs/            # CLI definitions
│   │   ├── claude.json
│   │   ├── codex.json
│   │   ├── gemini.json
│   │   └── opencode.json
│   └── roles/                  # Role-based system prompts
│       ├── planner.md
│       ├── codereviewer.md
│       ├── consensus.md
│       └── testgen.md
└── examples/
    └── consensus-workflow.md
```

### 2. Optional Claude Plugin Wrapper

**Decision:** Provide an optional Claude Code plugin wrapper for enhanced features.

**Rationale:**
- Core skill works everywhere via Agent Skills
- Claude users get bonus features: slash commands, hooks, better integration
- Maximum portability + enhanced experience where available

**Additional structure:**
```
.claude-plugin/
├── plugin.json                 # Claude metadata
├── commands/
│   └── orchestrate.md          # /orchestrate command
└── hooks/
    └── hooks.json              # Optional pre/post-tool hooks
```

### 3. tmux for Session Management

**Decision:** Use tmux as the orchestration layer for spawning and monitoring agents.

**Rationale:**
- Native session persistence and management
- Easy pane-based monitoring of multiple agents
- Rich API for creating, controlling, and reading from panes
- User can inspect tmux sessions during/after orchestration
- Works on all Unix-like systems

**Session Architecture:**
- Create session: `agent-orch-{timestamp}`
- Main pane: Orchestrator control
- Additional panes: One per spawned agent
- Monitor via `tmux capture-pane`
- Detect completion via output patterns or idle detection

### 4. CLI-Agnostic Configuration

**Decision:** JSON-based CLI registry similar to PAL MCP's `conf/cli_clients/` pattern.

**Rationale:**
- Easy to add new CLIs as they emerge
- Clear separation between CLI invocation and orchestration logic
- Configuration-driven rather than hardcoded
- Users can customize flags and behaviors

**CLI Config Format:**
```json
{
  "name": "claude",
  "command": "claude",
  "args": ["--output-format", "json", "--permission-mode", "acceptEdits"],
  "env": {},
  "output_format": "json",
  "roles": {
    "default": "references/roles/default.md",
    "planner": "references/roles/planner.md",
    "codereviewer": "references/roles/codereviewer.md",
    "consensus": "references/roles/consensus.md"
  }
}
```

### 5. Role-Based System Prompts

**Decision:** Store role prompts as markdown files in `references/roles/`.

**Rationale:**
- Borrowed from PAL MCP's proven pattern
- Markdown supports formatting, examples, code blocks
- Easy to version control and iterate
- Can include detailed instructions and edge cases

**Roles:**
- `planner.md` - Strategic planning, breaking down complex tasks
- `codereviewer.md` - Code analysis with severity levels
- `consensus.md` - Multi-perspective analysis and recommendation
- `testgen.md` - Test generation and coverage analysis
- `default.md` - General purpose assistance

### 6. Interaction Models

**Decision:** Support both explicit delegation and progressive disclosure.

**Approaches:**

**Explicit Delegation:**
```
"Get consensus on this plan using Gemini Pro and Codex"
→ User specifies exactly which CLIs and roles to use
```

**Progressive Disclosure:**
```
"Get consensus on this plan"
→ Skill triggers based on SKILL.md description
→ Orchestrator asks: "Which CLIs should I consult? (gemini/codex/claude/opencode)"
→ Asks: "Which models/thinking levels?"
→ Executes based on user answers
```

**Interactive Clarification:**
```
If intent unclear, orchestrator asks:
- Which CLIs to use?
- Which roles to assign?
- What context files to share?
- What models/thinking levels?
```

## Technical Architecture

### tmux Session Management

**Session Creation:**
```bash
# Create session with descriptive name
SESSION="agent-orch-$(date +%Y%m%d-%H%M%S)"
tmux new-session -d -s "$SESSION" -n main

# Spawn agent panes
tmux split-window -h -t "$SESSION:0"
tmux split-window -v -t "$SESSION:0"

# Each pane gets a CLI
tmux send-keys -t "$SESSION:0.1" "claude --output-format json" Enter
tmux send-keys -t "$SESSION:0.2" "codex exec --json" Enter
```

**Prompt Delivery:**
```bash
# Write prompt to temp file (avoids shell escaping issues)
PROMPT_FILE="/tmp/agent-prompt-$(uuidgen).md"
cat > "$PROMPT_FILE" <<EOF
# System Prompt
$(cat references/roles/consensus.md)

# User Request
${USER_REQUEST}

# Context Files
${FILE_REFERENCES}
EOF

# Pipe to CLI
tmux send-keys -t "$SESSION:0.1" "cat $PROMPT_FILE | claude --output-format json" Enter
```

**Output Monitoring:**
```bash
# Capture pane output periodically
tmux capture-pane -t "$SESSION:0.1" -p -S -100 > /tmp/agent-output-1.txt

# Check for completion markers:
# - JSON closing brace with no further output
# - Specific completion strings
# - Idle detection (no new output for N seconds)

# Parse JSON when complete
jq '.response' /tmp/agent-output-1.txt
```

**Subagent Monitoring:**
```bash
# Orchestrator can spawn subagents to monitor CLI panes
# This avoids blocking the main conversation flow
# One subagent per monitored pane, reporting back when ready
```

### CLI Registry and Invocation

**Supported CLIs (Initial):**
- `claude` - Claude Code CLI
- `codex` - OpenAI Codex CLI
- `gemini` - Google Gemini CLI
- `opencode` - OpenCode CLI

**Invocation Pattern:**
```bash
# Load CLI config
CONFIG=$(jq -r '.command, .args[]' references/cli-configs/claude.json)

# Construct command
CLI_CMD="$CONFIG"

# Add role-specific system prompt
ROLE_PROMPT=$(cat references/roles/consensus.md)

# Execute
echo "$ROLE_PROMPT\n\n$USER_PROMPT" | $CLI_CMD
```

**Output Format Handling:**
```bash
# Each CLI outputs JSON (where supported)
# Parse structured output:
{
  "status": "complete",
  "response": "...",
  "confidence": "high",
  "recommendations": [...]
}

# Fallback to text parsing if JSON unavailable
```

### Role System Implementation

**Role Prompt Structure:**

Each role prompt (`references/roles/{role}.md`) contains:

1. **Identity** - Who the agent is and what it specializes in
2. **Responsibilities** - What tasks it should perform
3. **Output Format** - How to structure responses
4. **Guidelines** - Best practices and constraints
5. **Examples** - Sample inputs and expected outputs

**Example: consensus.md**
```markdown
# Consensus Role

You are a consensus-building agent operating through the Agent Orchestrator.

## Responsibilities
- Analyze proposals from your assigned perspective (supportive/critical/neutral)
- Provide balanced technical analysis
- Identify trade-offs and risks
- Make clear recommendations

## Output Format
Provide your analysis in JSON format:
{
  "stance": "supportive|critical|neutral",
  "analysis": "...",
  "trade_offs": [...],
  "risks": [...],
  "recommendation": "..."
}

## Guidelines
- Be technically rigorous
- Consider multiple perspectives even within your stance
- Cite specific technical concerns or benefits
- Avoid reflexive agreement or disagreement

## Example
Input: "Should we migrate from REST to GraphQL?"
Output: [example JSON response]
```

### Completion Detection

**Strategies:**

1. **JSON Structure Detection**
   - Look for complete JSON objects
   - Validate with `jq` before accepting

2. **Completion Markers**
   - Specific strings: `<COMPLETE>`, `<SUMMARY>...</SUMMARY>`
   - Status fields: `"status": "complete"`

3. **Idle Detection**
   - No new output for N seconds (configurable)
   - Fallback when other methods unclear

4. **Token/Line Limits**
   - Capture fixed number of lines
   - Truncate at reasonable boundaries

### Result Synthesis

**Orchestrator combines multiple agent outputs:**

```bash
# Collect all agent responses
RESPONSES=()
for pane in "${PANES[@]}"; do
  output=$(tmux capture-pane -t "$pane" -p)
  RESPONSES+=("$output")
done

# Synthesize results
# - Compare recommendations
# - Identify consensus vs disagreements
# - Highlight key insights from each agent
# - Provide unified recommendation

# Return to user
cat <<EOF
## Consensus Analysis

### Agent 1 (Gemini Pro - Supportive)
${RESPONSES[0]}

### Agent 2 (Codex - Critical)
${RESPONSES[1]}

### Synthesis
[Orchestrator's unified recommendation]
EOF
```

## Implementation Plan

### Phase 1: Design Validation (Current)

1. ✅ Complete design specification
2. ⏳ Write to plan document
3. ⏳ **Test orchestration concept** - Spawn Codex with consensus role to review this plan
4. ⏳ Incorporate feedback and iterate

### Phase 2: Skill Development

Use official Anthropic skills for guidance:
- `plugin-dev:create-plugin` - End-to-end plugin creation workflow
- `plugin-dev:skill-development` - Skill development best practices

**Steps:**
1. Create `SKILL.md` following Agent Skills standard
2. Implement core orchestration scripts:
   - `scripts/orchestrate.sh` - Main entry point
   - `scripts/spawn-agent.sh` - CLI spawning
   - `scripts/monitor-tmux.sh` - Output monitoring
3. Create CLI configurations:
   - `references/cli-configs/claude.json`
   - `references/cli-configs/codex.json`
   - `references/cli-configs/gemini.json`
   - `references/cli-configs/opencode.json`
4. Write role prompts:
   - `references/roles/planner.md`
   - `references/roles/codereviewer.md`
   - `references/roles/consensus.md`
   - `references/roles/testgen.md`
5. Test with each CLI individually
6. Test multi-CLI orchestration scenarios

### Phase 3: Claude Plugin Wrapper (Optional)

1. Create `.claude-plugin/plugin.json` manifest
2. Add `/orchestrate` command in `commands/orchestrate.md`
3. Optional hooks for automation
4. Document Claude-specific features

### Phase 4: Documentation and Examples

1. README with installation and usage
2. Example workflows in `examples/`
3. Troubleshooting guide
4. CLI configuration guide for adding new CLIs

## Testing Strategy

### Pre-Implementation Test (Phase 1)

**Goal:** Validate the orchestration concept works before building the full skill.

**Approach:**
1. Write this design plan to markdown file
2. Manually test tmux + CLI spawning
3. Spawn Codex agent with consensus role
4. Have Codex review this design plan
5. Capture feedback via tmux monitoring
6. Iterate on design based on feedback

**Success Criteria:**
- tmux session creates successfully
- Codex spawns with JSON output format
- Prompt with role instructions delivered
- Output captured and parsed
- Consensus feedback is useful

### Post-Implementation Tests (Phase 2)

**Single CLI Tests:**
- Spawn claude with planner role
- Spawn codex with codereviewer role
- Spawn gemini with consensus role
- Spawn opencode with testgen role

**Multi-CLI Tests:**
- Consensus with 2 CLIs (different perspectives)
- Consensus with 3+ CLIs
- Parallel code review (multiple agents, same code)
- Sequential workflow (planner → reviewer → testgen)

**Error Handling Tests:**
- CLI not installed
- Invalid role specified
- Malformed JSON output
- CLI crashes or hangs
- Network issues (for cloud CLIs)

## Open Questions

1. **Subagent management** - Should the orchestrator spawn Claude Code subagents to monitor tmux panes, or use simple bash loops?
2. **Cost tracking** - Should we track token usage across agents? How to report?
3. **Parallel vs Sequential** - Default behavior for multi-agent tasks?
4. **User visibility** - Show tmux session to user, or hide and just show results?
5. **Error recovery** - Retry strategies if a CLI fails?

## Success Metrics

- ✅ Works across multiple CLIs (not just Claude)
- ✅ Reduces context window pollution via isolation
- ✅ Provides valuable multi-perspective insights
- ✅ Easy to add new CLIs via configuration
- ✅ Follows Agent Skills standard for portability
- ✅ Optional Claude Plugin provides enhanced experience

## Next Steps

1. **Immediate:** Get consensus review from Codex on this design
2. **After validation:** Use `plugin-dev:create-plugin` to scaffold the skill
3. **Implementation:** Build core orchestration scripts
4. **Testing:** Validate with each supported CLI
5. **Documentation:** Write comprehensive usage guide
6. **Release:** Publish to Agent Skills ecosystem

## References

- [Agent Skills Standard](https://agentskills.io/)
- [PAL MCP Server](https://github.com/BeehiveInnovations/pal-mcp-server) - Inspiration for clink tool
- [Claude Code Plugins](https://docs.anthropic.com/claude/docs/plugins)
- [OpenCode CLI](https://opencode.ai/docs/cli/)
- [Gemini CLI](https://github.com/google-gemini/gemini-cli)

---

**Status:** Ready for consensus review via Codex orchestration test
