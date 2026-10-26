#!/usr/bin/env bash
set -euo pipefail

# Installs local Git hooks for Techuboard
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK_PATH="$ROOT_DIR/.git/hooks/pre-push"

cat << 'EOF' > "$HOOK_PATH"
#!/usr/bin/env bash
set -euo pipefail

echo "🔍 Running Techuboard local pre-push validation gate..."
"$(git rev-parse --show-toplevel)/scripts/pre_push_check.sh"
EOF

chmod +x "$HOOK_PATH"
echo "✅ Git pre-push hook installed successfully at $HOOK_PATH"
