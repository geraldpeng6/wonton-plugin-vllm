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

run_case() { # <名字> <期望 offline 值> [vllm 参数…]
  local name="$1" want="$2" got
  shift 2
  PATH="$work/bin:$PATH" WONTON_MODEL_HUB="$work/hub" sh "$entry" serve "$@" 2>/dev/null
  got="$(cut -d= -f2 "$STUB_OUT")"
  if [[ "$got" == "$want" ]]; then
    echo "PASS $name（offline=$got）"
  else
    echo "FAIL $name：期望 offline=$want，得到 $got" >&2
    exit 1
  fi
}

served="$work/hub/models--Qwen--Qwen3-8B/snapshots/abc"
other="$work/hub/models--Other--Model/snapshots/def"
mkdir -p "$served" "$other"

# 半截下载：config 写完了、分片一个没有——不能判完整（这是判据修的 bug）
: >"$served/config.json"
run_case '只有空 config.json' 0 --model Qwen/Qwen3-8B

# 一片权重、config 没写完：还没到可装载的形状
rm "$served/config.json"
: >"$served/model-00001-of-00002.safetensors"
run_case '只有一片权重、无 config' 0 --model Qwen/Qwen3-8B

# 索引列了两个分片、只到了一个：判据要数分片
: >"$served/config.json"
cat >"$served/model.safetensors.index.json" <<'IDX'
{"weight_map": {"a.safetensors": "model-00001-of-00002.safetensors",
                "b.safetensors": "model-00002-of-00002.safetensors"}}
IDX
rm "$served/model-00001-of-00002.safetensors"
: >"$served/model-00002-of-00002.safetensors"
run_case '索引两片只到一片' 0 --model Qwen/Qwen3-8B

# 分片齐了：完整，离线装载
: >"$served/model-00001-of-00002.safetensors"
run_case '索引分片齐全' 1 --model Qwen/Qwen3-8B

# 换模型升级的现场：旧模型完整、新模型缺片——只能按 --model 指定的那个判
: >"$other/config.json"
: >"$other/model.safetensors"
rm "$served/model-00001-of-00002.safetensors"
run_case '别的模型完整也不顶替缺片的' 0 --model Qwen/Qwen3-8B
run_case '指定的那个完整就离线' 1 --model Other/Model

# 单文件权重模型：没有索引，model.safetensors 在即完整
rm "$served/model.safetensors.index.json"
: >"$served/model.safetensors"
run_case '单文件权重' 1 --model Qwen/Qwen3-8B

# 索引坏了（解析失败）：按不完整处理，走在线
rm "$served/model.safetensors"
: >"$served/model.safetensors.index.json"
echo 'not json' >"$served/model.safetensors.index.json"
run_case '索引损坏' 0 --model Qwen/Qwen3-8B

# 模型目录不存在（首装）：在线首跑
rm -rf "$work/hub"
run_case '无缓存目录' 0 --model Qwen/Qwen3-8B

# --model 给的是本地路径：不经 HF 缓存，不设离线开关
mkdir -p "$work/weights"
run_case '本地路径模型' 0 --model "$work/weights"

# 没传 --model：无从判，走在线
run_case '未指定模型' 0

echo '全部通过'
