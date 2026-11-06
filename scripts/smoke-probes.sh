# scripts/smoke.sh 的一项一项探测，跟着插件走。没写的项会 FAIL 并给出写法，不会默认放行。
# shellcheck shell=bash disable=SC2034
#（IDENTITY_NA、SMOKE_NOTE 由套件 smoke.sh 读取，这里只赋值。）
# 钩子只准用白名单里的东西：SMOKE_STATE/SMOKE_JAR/SMOKE_WEB_URL/SMOKE_OWNER/
# SMOKE_BASE/SMOKE_TOKEN/SMOKE_INSTANCE 七个变量和 web_get、dweb 两个助手；
# 不读 E2E_*，不调套件内部函数。本文件只用到 SMOKE_STATE 和 web_get。
#
# vLLM：sso=proxy，网关给每个已登录请求注入 `Authorization: Bearer <api_key>`；
# vLLM 没有用户和登录体系（IDENTITY_NA=1），身份完全由核心网关的会话保证。
# 持久数据是模型缓存：清单把模型放在数据目录的 models/ 子路径（spec 的
# ${WONTON_APP_DATA} 用法），data_write/data_check 验证它跨重装还在。
# 没有别的用户数据。
#
# before_install 可设 VLLM_MODEL_SRC 指向一个现成的模型缓存目录（HF_HOME 布局），
# 硬链接克隆进本实例的数据目录，省去重复下载；不设就由 vLLM 启动时自己下载。
IDENTITY_NA=1
SMOKE_NOTE="vLLM 没有用户体系；身份由核心网关会话保证"

app_models_dir() { # 实例数据目录里挂模型的子路径（id 里的点在路径里原样保留）
  echo "$SMOKE_STATE/data/apps/ai.vllm.vllm/models"
}

before_install() {
  local src="${VLLM_MODEL_SRC:-}" dst
  dst="$(app_models_dir)"
  if [[ -z "$src" ]]; then
    echo "VLLM_MODEL_SRC 没设，让 vLLM 首次启动时自己下模型"
    return 0
  fi
  [[ -d "$src" ]] || { echo "VLLM_MODEL_SRC 不是目录：$src"; return 1; }
  mkdir -p "$dst"
  cp -al "$src/." "$dst/"
  echo "已从 $src 硬链接克隆模型缓存（$(find "$dst" -type f ! -name '*.incomplete' ! -name '*.lock' | grep -c . || true) 个文件）"
}

# / 的响应是反代跳到 /docs 的 Swagger 页，页面上没有 vllm 字样（FastAPI 默认标题）；
# 用 vLLM 自己的 /version 断言身份（经网关时密钥已由代登录注入）。
web_assert() {
  local v
  v="$(web_get /version)" || { echo "/version 请求失败：$v"; return 1; }
  grep -qE '"version"\s*:\s*"[0-9]+(\.[0-9]+)+"' <<<"$v" ||
    { echo "/version 响应不像 vLLM：$(head -c 120 <<<"$v")"; return 1; }
}

# 数据探针：vLLM 的持久数据是模型缓存（用户下载的模型权重，装进数据目录的 models/）。
# data_write 把数据目录指纹记进 $SMOKE_STATE/data-marker；data_check 在重装（保数据）
# 之后核对缓存还在。指纹只记"文件名:大小"且跳过 .incomplete 和 .lock：
# HF 下载支持断点续传，已完成的不完整分片会被改名、锁文件用完即删，
# 只记完成的文件，后台还在下的新文件不影响核对。
data_write() {
  local dir out n
  dir="$(app_models_dir)"
  out="$SMOKE_STATE/data-marker"
  [[ -d "$dir" ]] || { echo "模型缓存目录不存在：$dir"; return 1; }
  {
    echo "dir=$dir"
    find "$dir" -type f ! -name '*.incomplete' ! -name '*.lock' -printf '%P\t%s\n' | sort
  } >"$out" || return 1
  n=$(tail -n +2 "$out" | grep -c . || true)
  (( n > 0 )) || { echo "数据目录里一个模型文件都没有：$dir"; return 1; }
  echo "标记写入 $out（$n 个文件）"
}

data_check() {
  local out dir path expect have n=0
  out="$SMOKE_STATE/data-marker"
  [[ -s "$out" ]] || { echo "没有 data_write 写的标记：$out"; return 1; }
  dir="$(sed -n 's/^dir=//p' "$out")"
  [[ -d "$dir" ]] || { echo "模型缓存目录没了：$dir"; return 1; }
  while IFS=$'\t' read -r path expect; do
    [[ -z "$path" || "$path" == dir=* ]] && continue
    have=$(stat -c %s "$dir/$path" 2>/dev/null || echo 0)
    (( have >= expect )) || { echo "缓存文件缩水或消失：$path（$have < $expect）"; return 1; }
    n=$((n + 1))
  done < <(tail -n +2 "$out")
  echo "重装后缓存完好：$n 个文件一个不少"
}
