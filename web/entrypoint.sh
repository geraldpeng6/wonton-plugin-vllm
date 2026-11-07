#!/bin/sh
# vLLM 插件的装载入口：模型缓存完整时离线装载（跳过 hf-mirror 的远端校验，
# 实测缓存命中时远端校验仍会发起大文件下载并挂死），缓存缺失时走在线首跑下载。
# 挂载点见 docker-compose.yml 的 entrypoint 配置；参数原样交给 vllm serve。
set -eu
hub=/data/models/huggingface/hub
complete=0
if [ -d "$hub" ]; then
  for f in "$hub"/models--*/snapshots/*/model.safetensors.index.json \
           "$hub"/models--*/snapshots/*/config.json; do
    [ -e "$f" ] || continue
    complete=1
  done
fi
if [ "$complete" = 1 ]; then
  echo "entrypoint: 模型缓存完整，离线装载（跳过远端校验）"
  HF_HUB_OFFLINE=1 exec vllm serve "$@"
fi
echo "entrypoint: 无完整模型缓存，在线首跑下载"
exec vllm serve "$@"
