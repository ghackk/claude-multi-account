#!/bin/bash
# ─── asciinema Demo Recording Script ─────────────────────────────────────
#
# HOW TO USE:
# 1. Install asciinema: pip install asciinema (or brew install asciinema)
# 2. Start recording: asciinema rec demo.cast
# 3. Run this script manually step by step (type each command yourself)
# 4. Stop recording: exit or Ctrl+D
# 5. Convert to GIF:
#    npm install -g svg-term-cli
#    svg-term --in demo.cast --out demo.svg --window
#    OR use https://gif.asciinema.org/ to convert online
#    OR use agg: cargo install agg && agg demo.cast demo.gif
#
# ALTERNATIVE (auto-typed demo using expect/pv):
#   Install: pip install asciinema
#   Record with this script: asciinema rec -c "bash marketing/demo-script.sh" demo.cast
#
# ─── DEMO FLOW ────────────────────────────────────────────────────────────
#
# Scene 1: Show the problem (3 seconds)
#   $ ls ~/.claude/
#   → Shows single config dir — locked to one account
#
# Scene 2: Launch multi-claude (5 seconds)
#   $ multi-claude
#   → Shows the menu with all accounts listed
#
# Scene 3: Create a new account (8 seconds)
#   Select option 2 → type "client-acme" → account created
#   → Shows "claude-client-acme" registered on PATH
#
# Scene 4: Direct launch (3 seconds)
#   $ claude-work
#   → Claude CLI opens with work profile (Ctrl+C to exit)
#
# Scene 5: Cloud backup (5 seconds)
#   Select option C → All profiles → shows backup code
#
# Scene 6: Show install options (3 seconds)
#   Show npm/pip/brew/scoop commands
#
# ─── COMMANDS TO TYPE DURING RECORDING ────────────────────────────────────

# Type these commands one by one during asciinema recording:

# 1. Show the problem
echo "# The problem: Claude CLI = one account at a time"
ls ~/.claude/ 2>/dev/null || echo "(single config directory)"
sleep 2

# 2. Launch the tool
echo ""
echo "# The solution: multi-claude"
sleep 1
# Now type: multi-claude
# Show the menu, then press 0 to exit

# 3. Direct launch
echo ""
echo "# Every profile works as a direct command:"
echo "$ claude-work    # launches work account"
echo "$ claude-personal  # launches personal account"
sleep 2

# 4. Install
echo ""
echo "# Install:"
echo "$ npm install -g @ghackk/multi-claude"
echo "$ pip install multi-claude"
echo "$ brew install ghackk/tap/multi-claude"
