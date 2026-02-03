#!/usr/bin/env bash
set -euo pipefail

# Test script to validate orchestration concept
# Spawns Codex with consensus role to review the design plan

SESSION="agent-orch-test-$(date +%Y%m%d-%H%M%S)"
PLAN_FILE="$(pwd)/docs/plans/2026-02-03-multi-agent-orchestrator-design.md"
OUTPUT_FILE="/tmp/codex-consensus-output-$(date +%Y%m%d-%H%M%S).txt"

echo "=== Agent Orchestrator Test ==="
echo "Session: $SESSION"
echo "Plan file: $PLAN_FILE"
echo "Output file: $OUTPUT_FILE"
echo ""

# Create consensus role prompt
CONSENSUS_PROMPT=$(cat <<'EOF'
# Consensus Role

You are a consensus-building agent reviewing an architectural design.

## Your Task

Review the attached design plan for a multi-agent orchestrator system. Analyze from a balanced perspective:

1. **Architectural Soundness** - Is the design technically sound?
2. **Trade-offs** - What are the key trade-offs in this approach?
3. **Risks** - What potential issues or challenges exist?
4. **Alternatives** - Are there better approaches to consider?
5. **Recommendations** - What changes or improvements would you suggest?

## Output Format

Provide your analysis in the following structure:

### Overall Assessment
[Your high-level opinion on the design]

### Strengths
- [List key strengths]

### Concerns
- [List concerns or potential issues]

### Trade-offs
- [Key trade-offs to consider]

### Alternatives to Consider
- [Alternative approaches worth exploring]

### Recommendations
- [Specific actionable recommendations]

Be technically rigorous and constructive. Focus on helping improve the design.

---

# Design Plan to Review

EOF
)

# Create prompt file with role + plan
PROMPT_FILE="/tmp/agent-prompt-$(uuidgen).md"
echo "$CONSENSUS_PROMPT" > "$PROMPT_FILE"
cat "$PLAN_FILE" >> "$PROMPT_FILE"

echo "1. Creating tmux session..."
tmux new-session -d -s "$SESSION" -n orchestrator

echo "2. Spawning Codex agent with consensus role..."
tmux send-keys -t "$SESSION:orchestrator" "cd ~/Code/Public/agent-orchestrator" Enter
tmux send-keys -t "$SESSION:orchestrator" "echo 'Starting Codex consensus review...'" Enter
tmux send-keys -t "$SESSION:orchestrator" "cat $PROMPT_FILE | codex exec --json --dangerously-bypass-approvals-and-sandbox 2>&1 | tee $OUTPUT_FILE" Enter

echo "3. Monitoring Codex output..."
echo ""
echo "To attach to the tmux session and watch live:"
echo "  tmux attach-session -t $SESSION"
echo ""
echo "To view output file:"
echo "  tail -f $OUTPUT_FILE"
echo ""
echo "Waiting for Codex to complete (this may take 1-2 minutes)..."

# Poll for completion
WAIT_TIME=0
MAX_WAIT=300  # 5 minutes max
while [ $WAIT_TIME -lt $MAX_WAIT ]; do
    sleep 5
    WAIT_TIME=$((WAIT_TIME + 5))

    # Check if output file has content and codex has finished
    if [ -f "$OUTPUT_FILE" ] && [ -s "$OUTPUT_FILE" ]; then
        # Check if last line suggests completion
        if grep -q "}" "$OUTPUT_FILE" 2>/dev/null; then
            # Wait a bit more to ensure output is complete
            sleep 3

            # Check if no new output in last 3 seconds
            SIZE_BEFORE=$(wc -c < "$OUTPUT_FILE" 2>/dev/null || echo 0)
            sleep 3
            SIZE_AFTER=$(wc -c < "$OUTPUT_FILE" 2>/dev/null || echo 0)

            if [ "$SIZE_BEFORE" -eq "$SIZE_AFTER" ]; then
                echo ""
                echo "✓ Codex consensus review complete!"
                break
            fi
        fi
    fi

    if [ $((WAIT_TIME % 15)) -eq 0 ]; then
        echo "  ... still waiting ($WAIT_TIME seconds elapsed)"
    fi
done

if [ $WAIT_TIME -ge $MAX_WAIT ]; then
    echo "⚠ Timeout waiting for Codex. Check output manually:"
    echo "  cat $OUTPUT_FILE"
fi

echo ""
echo "4. Displaying Codex consensus review:"
echo "═══════════════════════════════════════════════════════"
cat "$OUTPUT_FILE"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "Output saved to: $OUTPUT_FILE"
echo "tmux session: $SESSION (still running, 'tmux kill-session -t $SESSION' to close)"
echo ""
echo "Test complete! Review the feedback and iterate on the design."
