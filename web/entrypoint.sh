#!/bin/sh
# vLLM 插件的装载入口：模型缓存完整时离线装载（跳过 hf-mirror 的远端校验，
# 实测缓存命中时远端校验仍会发起大文件下载并挂死），缓存缺失时走在线首跑下载。
# 挂载点见 docker-compose.yml 的 entrypoint 配置；参数原样交给 vllm serve。
set -eu
hub="${VLLM_HUB_DIR:-/data/models/huggingface/hub}"
complete=0
# 完整=权重分片齐全：HF 下载先写 config.json 再下大分片，只看 config 存在会把
# 半截下载判成完整，离线模式缺分片直接 LocalEntryNotFoundError，unless-stopped
# 反复重启；不完整时走在线装载，在线能续传。判据测试见 scripts/tests/entrypoint-test.sh。
if [ -d "$hub" ]; then
  for model in "$hub"/models--*/snapshots/*/; do
    [ -d "$model" ] || continue
    [ -f "${model}config.json" ] || continue
    if [ -f "${model}model.safetensors.index.json" ]; then
      # 有索引的模型：weight_map 列出的每个分片都得在（缺一个就走在线续传）
      if python3 - "$model" <<'PY'
import json, os, sys
model = sys.argv[1]
index = json.load(open(os.path.join(model, "model.safetensors.index.json")))
ok = all(os.path.isfile(os.path.join(model, f))
         for f in set(index.get("weight_map", {}).values()))
sys.exit(0 if ok else 1)
PY
      then
        complete=1
      fi
    elif [ -f "${model}model.safetensors" ]; then
      # 单文件权重模型：权重在即完整
      complete=1
    fi
    if [ "$complete" = 1 ]; then
      break
    fi
  done
fi
if [ "$complete" = 1 ]; then
  echo "entrypoint: 模型缓存完整，离线装载（跳过远端校验）"
  HF_HUB_OFFLINE=1 exec vllm serve "$@"
fi
echo "entrypoint: 无完整模型缓存，在线首跑下载"
exec vllm serve "$@"
