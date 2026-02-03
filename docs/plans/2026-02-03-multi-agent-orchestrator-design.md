# Multi-Agent Orchestrator Design

**Date:** 2026-02-03
**Status:** Revised - Incorporating Codex Consensus Feedback
**Format:** Agent Skills Standard with Optional Claude Plugin Wrapper

## Overview

A CLI-agnostic skill that orchestrates multiple AI agent CLIs (Claude Code, OpenCode, Codex, Gemini CLI, etc.) to perform collaborative tasks such as consensus building, parallel code reviews, test generation, and multi-perspective analysis. Uses **direct subprocess invocation** for reliability, **subagent architecture** for context isolation, and role-based system prompts for specialized agent personas. Optional tmux mode provides real-time visibility for debugging.

## Motivation

Current limitations:
- Single AI agent perspective can miss issues or approaches
- Context window pollution from large exploratory tasks
- No easy way to get consensus across different AI models/providers
- Manual context switching between different CLI tools
- No standard way to orchestrate multiple agents

**Agent Orchestrator solves this by:**
- Enabling any compatible CLI to orchestrate other CLIs
- Providing clean context isolation via **subagent architecture**
- Using **direct subprocess invocation** for reliability and security
- Supporting role-based personas (planner, codereviewer, consensus, testgen)
- Working across the entire Agent Skills ecosystem (Claude, OpenCode, Codex, Gemini, Cursor, etc.)
- Allowing explicit delegation ("use gemini and codex for consensus") and progressive disclosure (auto-triggering)
- Keeping main agent context clean (only sees request + summary)

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

### 3. Direct CLI Invocation with Optional tmux

**Decision:** Use direct subprocess invocation as the primary approach, with optional tmux for visibility.

**Rationale:**
- **More reliable:** Standard stdin/stdout pipes instead of tmux scraping
- **Simpler:** Built-in process management, no tmux dependency
- **Better security:** Direct file descriptors, no ANSI escape code issues
- **Works everywhere:** CI/CD, containers, headless environments
- **Easier error handling:** Exit codes, stderr capture, timeouts
- **Addresses Codex feedback:** Eliminates tmux parsing brittleness

**Primary Architecture (Direct Invocation):**
```bash
# Spawn CLI as subprocess
cat prompt.md | codex exec --json > output.json 2>&1 &
PID=$!

# Monitor process
timeout 120 tail -f output.json &
wait $PID

# Parse result
jq -r '.response' output.json
```

**Optional tmux Mode:**
- User flag: `--use-tmux` for real-time visibility
- Debugging complex multi-agent scenarios
- Interactive exploration
- NOT required for core functionality

### 4. Subagent Architecture for Context Isolation

**Decision:** Orchestrator runs as a subagent to keep main agent context clean.

**Rationale:**
- Main agent only sees: user request + final summary
- Orchestrator subagent handles heavy lifting in isolated context
- File reading, CLI spawning, output parsing don't pollute main context
- Scales to many agents without bloating main context window
- Matches PAL MCP's clink pattern

**Architecture Flow:**
```
User's Main Agent (Claude Code)
  ↓ invokes orchestrator skill
Orchestrator Subagent (isolated context)
  ↓ reads plan files (large docs stay in subagent)
  ↓ spawns CLI processes via bash
  ├─→ Codex exec (isolated process + context)
  ├─→ Gemini CLI (isolated process + context)
  └─→ Claude Code (isolated process + context)
  ↓ monitors outputs (in subagent context)
  ↓ synthesizes consensus (in subagent context)
  ↓ returns clean summary
Main Agent receives: "Consensus: [200 word summary]"
```

**Benefits:**
- ✅ Main agent context stays lean (10-20 tokens for summary)
- ✅ Orchestrator can read 2000-line plan files without bloating main context
- ✅ Multiple agent outputs stay isolated
- ✅ Error isolation (orchestrator failures don't break main agent)
- ✅ Enables complex multi-agent workflows

### 5. Security & Reliability

**Decision:** Address security and completion detection concerns before building.

**Based on Codex consensus feedback:**

**Security Hardening:**
```bash
# Secure temp directory (not /tmp)
SECURE_DIR=$(mktemp -d -t agent-orch.XXXXXX)
chmod 700 "$SECURE_DIR"
trap "rm -rf $SECURE_DIR" EXIT

# Input sanitization
sanitize_cli_config() {
  # Validate JSON schema
  # Escape shell metacharacters
  # Whitelist allowed commands
}

# Environment isolation
env -i PATH="$PATH" HOME="$HOME" \
  codex exec --json < "$SECURE_DIR/prompt.md"
```

**Explicit Completion Markers:**
```markdown
# In role prompts (consensus.md, codereviewer.md, etc.)

## Output Format

End your response with:
<AGENT_COMPLETE>
{
  "status": "complete",
  "confidence": "high",
  "response": "...",
  "recommendations": [...]
}
</AGENT_COMPLETE>
```

**Response Envelope Standard:**
```json
{
  "agent": "codex",
  "role": "consensus",
  "timestamp": "2026-02-03T14:56:42Z",
  "status": "complete",
  "completion_marker": "</AGENT_COMPLETE>",
  "response": {
    "overall_assessment": "...",
    "strengths": [...],
    "concerns": [...],
    "recommendations": [...]
  },
  "metadata": {
    "tokens": 576,
    "duration_seconds": 12
  }
}
```

**Error Handling:**
- Timeouts: 120s default, configurable per CLI
- Retries: 1 retry for transient failures (network, rate limits)
- Fallback: Continue with available agents if one fails
- Error taxonomy: `TIMEOUT`, `CLI_NOT_FOUND`, `AUTH_FAILURE`, `PARSE_ERROR`

### 6. CLI-Agnostic Configuration

**Decision:** JSON-based CLI registry with capability metadata.

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

### Orchestrator Subagent Flow

**High-Level Execution:**
```
1. Main Agent: "Get consensus on plan.md from Codex and Gemini"
2. Orchestrator Skill Triggers (via SKILL.md description matching)
3. Main Agent spawns Orchestrator Subagent (Task tool)
4. Orchestrator Subagent:
   - Reads plan.md (large file in subagent context)
   - Prepares role prompts for each CLI
   - Spawns CLI processes (direct invocation)
   - Monitors outputs (completion markers)
   - Synthesizes consensus
5. Returns to Main Agent: "Consensus summary: ..." (200 words)
6. Main Agent shows user clean summary
```

### Direct CLI Process Management

**Spawning CLI Agents:**
```bash
#!/usr/bin/env bash
spawn_agent() {
  local cli=$1 role=$2 prompt_file=$3 output_file=$4

  # Secure temp directory
  SECURE_DIR=$(mktemp -d -t agent-orch.XXXXXX)
  chmod 700 "$SECURE_DIR"
  trap "rm -rf $SECURE_DIR" EXIT

  # Load CLI config
  local config=$(cat "references/cli-configs/${cli}.json")
  local command=$(echo "$config" | jq -r '.command')
  local args=$(echo "$config" | jq -r '.args[]')

  # Prepare role prompt
  local role_prompt=$(cat "references/roles/${role}.md")
  cat > "$SECURE_DIR/full-prompt.md" <<EOF
$role_prompt

---

$(<"$prompt_file")
EOF

  # Spawn CLI as background process
  cat "$SECURE_DIR/full-prompt.md" | \
    env -i PATH="$PATH" HOME="$HOME" \
    $command $args > "$output_file" 2>&1 &

  echo $!  # Return PID
}

# Example: Spawn Codex with consensus role
CODEX_PID=$(spawn_agent "codex" "consensus" "user-request.md" "codex-output.json")
GEMINI_PID=$(spawn_agent "gemini" "consensus" "user-request.md" "gemini-output.json")
```

**Monitoring and Completion Detection:**
```bash
monitor_agent() {
  local pid=$1 output_file=$2 timeout=${3:-120}

  local elapsed=0
  local last_size=0

  while kill -0 $pid 2>/dev/null && [ $elapsed -lt $timeout ]; do
    sleep 2
    elapsed=$((elapsed + 2))

    # Check for explicit completion marker
    if grep -q '</AGENT_COMPLETE>' "$output_file" 2>/dev/null; then
      wait $pid
      return 0
    fi

    # Idle detection (fallback)
    local current_size=$(wc -c < "$output_file" 2>/dev/null || echo 0)
    if [ $current_size -gt 0 ] && [ $current_size -eq $last_size ]; then
      # No growth for 4 seconds, likely complete
      sleep 2
      if [ $(wc -c < "$output_file") -eq $current_size ]; then
        wait $pid
        return 0
      fi
    fi
    last_size=$current_size
  done

  # Timeout or process died
  kill $pid 2>/dev/null
  return 1
}

# Monitor both agents
monitor_agent $CODEX_PID "codex-output.json" &
monitor_agent $GEMINI_PID "gemini-output.json" &
wait  # Wait for both monitors
```

**Parallel Execution:**
```bash
# Spawn multiple agents in parallel
spawn_consensus() {
  local clis=("$@")
  local pids=()
  local outputs=()

  for cli in "${clis[@]}"; do
    local output="/tmp/agent-orch-$$-${cli}-output.json"
    local pid=$(spawn_agent "$cli" "consensus" "request.md" "$output")
    pids+=($pid)
    outputs+=($output)
  done

  # Monitor all
  for i in "${!pids[@]}"; do
    monitor_agent "${pids[$i]}" "${outputs[$i]}" &
  done
  wait

  # Collect results
  for output in "${outputs[@]}"; do
    if [ -f "$output" ]; then
      extract_response "$output"
    fi
  done
}

# Usage: spawn_consensus codex gemini claude
```

### Output Parsing and Result Extraction

**Extract Completion Marker Content:**
```bash
extract_response() {
  local output_file=$1

  # Strip ANSI codes
  local clean=$(sed 's/\x1b\[[0-9;]*m//g' "$output_file")

  # Extract content between <AGENT_COMPLETE> markers
  if echo "$clean" | grep -q '<AGENT_COMPLETE>'; then
    echo "$clean" | \
      sed -n '/<AGENT_COMPLETE>/,/<\/AGENT_COMPLETE>/p' | \
      sed '1d;$d' | \  # Remove marker lines
      jq -r '.'        # Parse JSON
  else
    # Fallback: Try to parse entire output as JSON
    echo "$clean" | jq -r '.' 2>/dev/null || echo "$clean"
  fi
}
```

**Supported CLIs (Initial):**
- `claude` - Claude Code CLI
  - Output: `--output-format json`
  - Supports: System prompts, streaming, explicit completion
- `codex` - OpenAI Codex CLI
  - Output: `--json` or `exec --json`
  - Supports: JSON output, model selection
- `gemini` - Google Gemini CLI
  - Output: `--output-format json`
  - Supports: Web search, 1M context, multimodal
- `opencode` - OpenCode CLI
  - Output: `-f json` or `--format json`
  - Supports: 75+ LLM providers, multi-session

### Role System Implementation

**Role Prompt Structure:**

Each role prompt (`references/roles/{role}.md`) contains:

1. **Identity** - Who the agent is and what it specializes in
2. **Responsibilities** - What tasks it should perform
3. **Output Format** - How to structure responses
4. **Guidelines** - Best practices and constraints
5. **Examples** - Sample inputs and expected outputs

**Example: consensus.md** (updated with explicit completion marker)
```markdown
# Consensus Role

You are a consensus-building agent operating through the Agent Orchestrator.

## Responsibilities
- Analyze proposals from your assigned perspective (supportive/critical/neutral)
- Provide balanced technical analysis
- Identify trade-offs and risks
- Make clear recommendations

## Output Format

**CRITICAL: You MUST end your response with the completion marker.**

End your response with:
<AGENT_COMPLETE>
{
  "status": "complete",
  "confidence": "high|medium|low",
  "stance": "supportive|critical|neutral",
  "overall_assessment": "...",
  "strengths": ["...", "..."],
  "concerns": ["...", "..."],
  "trade_offs": ["...", "..."],
  "alternatives": ["...", "..."],
  "recommendations": ["...", "..."]
}
</AGENT_COMPLETE>

## Guidelines
- Be technically rigorous
- Consider multiple perspectives even within your stance
- Cite specific technical concerns or benefits
- Avoid reflexive agreement or disagreement
- **Always include the completion marker** - the orchestrator depends on it

## Example
Input: "Should we migrate from REST to GraphQL?"
Output: [example JSON response]
```

### Completion Detection

**Primary Strategy: Explicit Markers**

All role prompts require `<AGENT_COMPLETE>` markers (addresses Codex feedback on reliability):

```bash
# Wait for explicit completion marker
while ! grep -q '</AGENT_COMPLETE>' "$output_file" 2>/dev/null; do
  if ! kill -0 $pid 2>/dev/null; then
    # Process died without completing
    return 1
  fi

  if [ $elapsed -gt $timeout ]; then
    # Timeout reached
    kill $pid
    return 1
  fi

  sleep 2
  elapsed=$((elapsed + 2))
done

# Marker found, extract content
extract_response "$output_file"
```

**Fallback Strategy: Idle Detection**

If CLI doesn't support markers or role prompt is incomplete:

1. **Output size stability** - No growth for 4+ seconds
2. **Process exit** - Process terminates normally
3. **Timeout** - Configurable per CLI (default 120s)

**Error Cases:**
- No marker + no output growth + timeout → Treat as failure
- Marker present but malformed JSON → Log error, return raw text
- Process crash → Capture stderr, report error to orchestrator

### Result Synthesis

**Orchestrator subagent combines multiple agent outputs:**

```bash
synthesize_consensus() {
  local outputs=("$@")
  local synthesis_file=$(mktemp)

  # Parse each agent response
  declare -A agents
  for output in "${outputs[@]}"; do
    local cli=$(basename "$output" | cut -d'-' -f1)
    local response=$(extract_response "$output")
    agents[$cli]="$response"
  done

  # Orchestrator subagent analyzes:
  # 1. Points of agreement across agents
  # 2. Key differences in perspective
  # 3. Unique insights from each agent
  # 4. Confidence levels
  # 5. Unified recommendation

  cat > "$synthesis_file" <<EOF
## Consensus Summary

### Agreement
$(find_common_points "${agents[@]}")

### Key Differences
$(find_divergent_views "${agents[@]}")

### Unique Insights
$(extract_unique_contributions "${agents[@]}")

### Recommendation
$(generate_unified_recommendation "${agents[@]}")

---
Consulted: ${!agents[@]}
Confidence: $(calculate_overall_confidence "${agents[@]}")
EOF

  cat "$synthesis_file"
}

# Return clean summary to main agent (200-300 words max)
# Main agent only sees this summary, not individual agent outputs
```

**Context Isolation:**
- Individual agent outputs (2000+ tokens each): Stay in orchestrator subagent context
- File reading (large plan docs): Stay in orchestrator subagent context
- Synthesis logic: Happens in orchestrator subagent context
- Final summary (200-300 words): Returned to main agent

**Main agent receives:**
```
Consensus achieved from Codex and Gemini on design plan:

[3-4 key agreement points]
[2-3 areas of divergence]
[Unified recommendation]

Overall confidence: High
```

## Implementation Plan

### Phase 1: Design Validation (Completed)

1. ✅ Complete design specification
2. ✅ Write to plan document
3. ✅ **Test orchestration concept** - Spawned Codex with consensus role to review plan
4. ✅ Incorporate Codex feedback:
   - Switch to direct CLI invocation (more reliable)
   - Add subagent architecture (context isolation)
   - Implement security hardening (secure temp files)
   - Use explicit completion markers (deterministic detection)

### Phase 2: Skill Development

Use official Anthropic skills for guidance:
- `plugin-dev:create-plugin` - End-to-end plugin creation workflow
- `plugin-dev:skill-development` - Skill development best practices

**Updated Steps:**
1. **Create `SKILL.md`** following Agent Skills standard
   - Description triggers on: "consensus", "orchestrate", "multi-agent"
   - Instructions to spawn orchestrator subagent
   - Reference to bash scripts for actual work

2. **Implement core orchestration scripts:**
   - `scripts/orchestrate.sh` - Main orchestrator subagent logic
   - `scripts/spawn-agent.sh` - Direct CLI subprocess spawning with security
   - `scripts/monitor-agent.sh` - Completion detection (explicit markers + idle fallback)
   - `scripts/synthesize.sh` - Result aggregation and summary generation
   - `scripts/utils.sh` - Secure temp files, JSON parsing, ANSI stripping

3. **Create CLI configurations with capabilities:**
   - `references/cli-configs/claude.json` (supports JSON, system prompts)
   - `references/cli-configs/codex.json` (supports JSON, model selection)
   - `references/cli-configs/gemini.json` (supports JSON, web search, 1M context)
   - `references/cli-configs/opencode.json` (supports JSON, 75+ providers)

4. **Write role prompts with completion markers:**
   - `references/roles/planner.md` (with `<AGENT_COMPLETE>` marker)
   - `references/roles/codereviewer.md` (with `<AGENT_COMPLETE>` marker)
   - `references/roles/consensus.md` (with `<AGENT_COMPLETE>` marker)
   - `references/roles/testgen.md` (with `<AGENT_COMPLETE>` marker)

5. **Test individual CLI invocation:**
   - Claude Code with planner role
   - Codex with codereviewer role
   - Gemini with consensus role
   - OpenCode with testgen role

6. **Test multi-CLI orchestration:**
   - 2-CLI consensus (Codex + Gemini)
   - 3-CLI consensus (Claude + Codex + Gemini)
   - Parallel execution validation
   - Context isolation verification

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

### Pre-Implementation Test (Phase 1) - ✅ Completed

**Goal:** Validate the orchestration concept works before building the full skill.

**Results:**
✅ Created orchestration test script (`test-orchestration.sh`)
✅ Spawned Codex with consensus role successfully
✅ Delivered design plan via stdin pipe (secure approach)
✅ Captured structured JSON output with completion marker
✅ Extracted comprehensive consensus feedback
✅ Validated core mechanics work (process spawning, monitoring, parsing)

**Key Learnings:**
1. Direct CLI invocation is more reliable than tmux scraping
2. Explicit `<AGENT_COMPLETE>` markers work perfectly
3. JSON parsing from CLI output is straightforward
4. Process monitoring via background jobs is simple
5. Codex provided excellent architectural feedback

**Codex Feedback Incorporated:**
- Security hardening (secure temp dirs, env isolation)
- Explicit completion markers (deterministic detection)
- Direct subprocess invocation (more reliable than tmux)
- Response envelope standardization

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

## Resolved Design Decisions

1. ✅ **Subagent architecture** - Orchestrator runs as subagent, spawns CLIs as direct subprocesses
2. ✅ **Process management** - Direct invocation, not tmux (more reliable)
3. ✅ **Completion detection** - Explicit `<AGENT_COMPLETE>` markers (deterministic)
4. ✅ **Security** - Secure temp directories, env isolation, input sanitization
5. ✅ **Context isolation** - Orchestrator subagent keeps main agent context clean

## Open Questions (For Implementation)

1. **Cost tracking** - Should we track token usage across agents? How to report?
   - Could parse usage from JSON responses where available
   - Log to file for post-analysis
   - Optional reporting to user

2. **Parallel vs Sequential** - Default behavior for multi-agent tasks?
   - Consensus: Parallel (faster, independent perspectives)
   - Code review: Sequential or parallel (configurable)
   - Planning: Sequential (build on previous output)

3. **User visibility** - Show progress updates?
   - Main agent sees: "Consulting Codex and Gemini..."
   - Optional verbose mode shows intermediate updates
   - Default: Clean summary only

4. **Error recovery** - Retry strategies?
   - Network/auth errors: 1 retry after 5s
   - Timeout: No retry (likely model issue)
   - CLI not found: Fail fast, clear error message
   - Partial success: Continue with available agents

5. **Optional tmux mode** - When to enable?
   - User flag: `--use-tmux` for debugging
   - Automatically for interactive exploration?
   - Document as advanced feature

## Success Metrics

**Validated:**
- ✅ Core mechanics work (process spawning, monitoring, parsing)
- ✅ Direct CLI invocation is reliable
- ✅ Explicit completion markers are deterministic
- ✅ JSON output parsing is straightforward
- ✅ Codex consensus feedback confirmed design soundness

**To Validate During Implementation:**
- ⏳ Works across multiple CLIs (Claude, Codex, Gemini, OpenCode)
- ⏳ Reduces context window pollution via subagent architecture
- ⏳ Provides valuable multi-perspective insights
- ⏳ Easy to add new CLIs via configuration
- ⏳ Follows Agent Skills standard for portability
- ⏳ Security hardening prevents vulnerabilities
- ⏳ Optional Claude Plugin provides enhanced experience

## Next Steps

1. ✅ **Complete design specification**
2. ✅ **Validate orchestration concept** (Codex consensus review)
3. ✅ **Incorporate feedback** (direct invocation, subagents, security)
4. ⏳ **Update design document** (current task)
5. ⏳ **Commit updated design**
6. ⏳ **Use `plugin-dev:create-plugin`** to scaffold the skill
7. ⏳ **Implement core scripts** with security and reliability improvements
8. ⏳ **Test across multiple CLIs** (Claude, Codex, Gemini, OpenCode)
9. ⏳ **Create example workflows**
10. ⏳ **Documentation** and README
11. ⏳ **Publish to Agent Skills ecosystem**

## References

- [Agent Skills Standard](https://agentskills.io/)
- [PAL MCP Server](https://github.com/BeehiveInnovations/pal-mcp-server) - Inspiration for clink tool
- [Claude Code Plugins](https://docs.anthropic.com/claude/docs/plugins)
- [OpenCode CLI](https://opencode.ai/docs/cli/)
- [Gemini CLI](https://github.com/google-gemini/gemini-cli)

---

**Status:** Design validated and updated with Codex feedback - Ready for implementation

**Changelog:**
- 2026-02-03: Initial design with tmux-based approach
- 2026-02-03: Validated with Codex consensus review
- 2026-02-03: **Major revision** - Switched to direct CLI invocation, added subagent architecture, implemented security hardening, added explicit completion markers
