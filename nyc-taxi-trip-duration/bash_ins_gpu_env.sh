#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="install.log"
STATE_FILE="state.json"

# =========================
# 🪵 logging
# =========================
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# =========================
# 🧠 state helpers
# =========================
is_done() {
    grep -q "\"$1\": true" "$STATE_FILE" 2>/dev/null
}

mark_done() {
    if [ ! -f "$STATE_FILE" ]; then
        echo "{}" > "$STATE_FILE"
    fi

    tmp=$(mktemp)
    jq ". + {\"$1\": true}" "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

# =========================
# 🔁 retry wrapper
# =========================
retry() {
    local n=0
    local max=5
    local delay=10

    until [ $n -ge $max ]; do
        "$@" 2>&1 | tee -a "$LOG_FILE" && return 0

        n=$((n+1))
        echo "⚠️ Attempt $n failed: $*"
        sleep $delay
        delay=$((delay * 2))
    done

    echo "❌ FAILED after $max attempts: $*" | tee -a "$LOG_FILE"
    return 1
}

# =========================
# ⚙️ env tuning
# =========================
export UV_HTTP_TIMEOUT=120
export UV_CONCURRENT_DOWNLOADS=8
export PIP_DEFAULT_TIMEOUT=120
export UV_CACHE_DIR="$HOME/.cache/uv"
export PIP_CACHE_DIR="$HOME/.cache/pip"
export CUPY_CACHE_DIR="$HOME/.cache/cupy"

log "🚀 Starting GPU environment setup..."

# =========================
# 🥇 STEP 1: uv sync (GPU stack)
# =========================
if ! is_done "uv_sync"; then
    log "📦 Running uv sync..."
    retry uv sync 
    mark_done "uv_sync"
else
    log "✔ uv sync already done"
fi

# =========================
# 🥈 STEP 2: ML core stack
# =========================
if ! is_done "ml_core"; then
    log "📊 Installing ML core stack..."
    retry uv add numpy pandas scikit-learn scipy joblib 
    mark_done "ml_core"
else
    log "✔ ML core already done"
fi

# =========================
# 🥉 STEP 3: visualization
# =========================
if ! is_done "viz"; then
    log "📈 Installing visualization stack..."
    retry uv add matplotlib seaborn plotly tabulate 
    mark_done "viz"
else
    log "✔ visualization already done"
fi

# =========================
# 🧠 STEP 4: ML extras
# =========================
if ! is_done "ml_extra"; then
    log "🤖 Installing ML extras..."
    retry uv add optuna statsmodels xgboost 
    mark_done "ml_extra"
else
    log "✔ ML extras already done"
fi

# =========================
# 📓 STEP 5: dev tools
# =========================
if ! is_done "dev"; then
    log "📓 Installing dev tools..."
    retry uv add ipykernel ipywidgets nbdime 
    mark_done "dev"
else
    log "✔ dev tools already done"
fi

# =========================
# ⚠️ STEP 6: kaggle (light, no datasets)
# =========================
if ! is_done "kaggle"; then
    log "📦 Installing kaggle CLI..."
    retry uv add "kaggle<2.0.0" pandas-stubs pynvim 
    mark_done "kaggle"
else
    log "✔ kaggle already done"
fi

# =========================
# 🧪 FINAL VALIDATION
# =========================
if ! is_done "validate"; then
    log "🧪 Running validation..."

python << 'EOF' 2>&1 | tee -a "$LOG_FILE"
import cupy as cp
import cudf

print("CUDA check:", cp.cuda.runtime.getDeviceCount())

df = cudf.DataFrame({"a":[1,2,3]})
print("cuDF OK:", df)
EOF

    mark_done "validate"
else
    log "✔ validation already done"
fi

log "🎉 GPU environment setup complete!"
