#!/usr/bin/env bash
# 装载入口 web/entrypoint.sh 的缓存判据测试：不起 Docker、不装 vLLM，
# 用桩 vllm 命令记录是否进入离线装载，按缓存目录的形状断言判据。
# CI 的 check.yml 里单独跑（scripts/tests/ 不在 ShellCheck 的 scripts/*.sh 范围里，但保持干净）。
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
entry="$root/web/entrypoint.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/bin"
cat >"$work/bin/vllm" <<'STUB'
#!/usr/bin/env bash
echo "offline=${HF_HUB_OFFLINE:-0}" > "$STUB_OUT"
STUB
chmod +x "$work/bin/vllm"
export STUB_OUT="$work/stub.out"

run_case() { # <名字> <期望 offline 值>
  local name="$1" want="$2" got
  HF_HUB_OFFLINE= PATH="$work/bin:$PATH" VLLM_HUB_DIR="$work/hub" sh "$entry" serve 2>/dev/null
  got="$(cut -d= -f2 "$STUB_OUT")"
  if [[ "$got" == "$want" ]]; then
    echo "PASS $name（offline=$got）"
  else
    echo "FAIL $name：期望 offline=$want，得到 $got" >&2
    exit 1
  fi
}

model="$work/hub/models--test/snapshots/abc"
mkdir -p "$model"

# 半截下载：config 写完了、分片一个没有——不能判完整（这是判据修的 bug）
: >"$model/config.json"
run_case '只有空 config.json' 0

# 一片权重、config 没写完：还没到可装载的形状
rm "$model/config.json"
: >"$model/model-00001-of-00002.safetensors"
run_case '只有一片权重、无 config' 0

# 索引列了两个分片、只到了一个：判据要数分片
: >"$model/config.json"
cat >"$model/model.safetensors.index.json" <<'IDX'
{"weight_map": {"a.safetensors": "model-00001-of-00002.safetensors",
                "b.safetensors": "model-00002-of-00002.safetensors"}}
IDX
rm "$model/model-00001-of-00002.safetensors"
: >"$model/model-00002-of-00002.safetensors"
run_case '索引两片只到一片' 0

# 分片齐了：完整，离线装载
: >"$model/model-00001-of-00002.safetensors"
run_case '索引分片齐全' 1

# 单文件权重模型：没有索引，model.safetensors 在即完整
rm "$model"/model-*.safetensors "$model/model.safetensors.index.json"
: >"$model/model.safetensors"
run_case '单文件权重' 1

# 索引坏了（解析失败）：按不完整处理，走在线
rm "$model/model.safetensors"
: >"$model/model.safetensors.index.json"
echo 'not json' >"$model/model.safetensors.index.json"
: >"$model/model.safetensors"
run_case '索引损坏' 0

# 没有缓存目录：在线首跑
rm -rf "$work/hub"
run_case '无缓存目录' 0

echo '全部通过'
