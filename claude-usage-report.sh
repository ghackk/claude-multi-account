#!/bin/bash
SOURCE=${BASH_SOURCE[0]}
while [ -L "$SOURCE" ]; do BASE=$(cd -P "$(dirname "$SOURCE")" && pwd); SOURCE=$(readlink "$SOURCE"); [[ $SOURCE != /* ]] && SOURCE="$BASE/$SOURCE"; done
REPORT_ROOT=$(cd -P "$(dirname "$SOURCE")" && pwd)
command -v node >/dev/null 2>&1 || { [ "${1:-}" = --install ] && echo 'Usage history needs Node.js 22.13 or newer.' >&2; exit 0; }
REPORT_NODE=$(command -v node)
"$REPORT_NODE" -e 'const [a,b]=process.versions.node.split(".").map(Number); process.exit(a>22 || (a===22 && b>=13) ? 0 : 1)' || {
    echo 'Usage history needs Node.js 22.13 or newer. Upgrade Node.js and reopen multi-claude.' >&2; exit 1;
}
case "${1:-}" in
  --install)
    "$REPORT_NODE" --disable-warning=ExperimentalWarning "$REPORT_ROOT/usage/install.js" || exit 1
    if [ "$(uname -s)" = Darwin ]; then
      if [ ! -f "$HOME/claude-usage-history/reporting-disabled" ]; then
        "$REPORT_NODE" "$REPORT_ROOT/usage/schedule.js" enable || exit 1
      fi
    elif command -v crontab >/dev/null 2>&1; then
      # Keep unrelated cron entries and the Node path (cron has a minimal PATH).
      REPORT_CRON=$(mktemp)
      crontab -l 2>/dev/null | sed '/# multi-claude-usage$/d' > "$REPORT_CRON"
      if [ ! -f "$HOME/claude-usage-history/reporting-disabled" ]; then
        printf '*/30 * * * * PATH="%s:/usr/local/bin:/usr/bin:/bin" /bin/bash "%s/claude-accounts/claude-usage-report.sh" >/dev/null 2>&1 # multi-claude-usage\n' "$(dirname "$REPORT_NODE")" "$HOME" >> "$REPORT_CRON"
      fi
      crontab "$REPORT_CRON"; REPORT_CRON_STATUS=$?; rm -f "$REPORT_CRON"
      [ "$REPORT_CRON_STATUS" -eq 0 ] || exit "$REPORT_CRON_STATUS"
    else
      echo 'crontab is unavailable; launchers and session hooks still collect usage.' >&2
    fi
    bash "$HOME/claude-accounts/claude-usage-report.sh" --background ;;
  --disable)
    "$REPORT_NODE" --disable-warning=ExperimentalWarning "$REPORT_ROOT/usage/report.js" disable
    if [ "$(uname -s)" = Darwin ]; then
      "$REPORT_NODE" "$REPORT_ROOT/usage/schedule.js" disable
    elif command -v crontab >/dev/null 2>&1; then (crontab -l 2>/dev/null | sed '/# multi-claude-usage$/d') | crontab -; fi ;;
  --enable)
    "$REPORT_NODE" --disable-warning=ExperimentalWarning "$REPORT_ROOT/usage/report.js" enable
    bash "$REPORT_ROOT/claude-usage-report.sh" --install ;;
  --dashboard)
    if command -v open >/dev/null 2>&1; then open https://pair.ghackk.com/; elif command -v xdg-open >/dev/null 2>&1; then xdg-open https://pair.ghackk.com/; else echo https://pair.ghackk.com/; fi ;;
  --background)
    [ "${MULTI_CLAUDE_NO_REPORT:-}" = 1 ] && exit 0
    nohup "$REPORT_NODE" --disable-warning=ExperimentalWarning "$REPORT_ROOT/usage/report.js" >/dev/null 2>&1 </dev/null & ;;
  *) exec "$REPORT_NODE" --disable-warning=ExperimentalWarning "$REPORT_ROOT/usage/report.js" "$@" ;;
esac
