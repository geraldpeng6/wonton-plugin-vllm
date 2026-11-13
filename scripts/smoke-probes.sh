# scripts/smoke.sh 的一项一项探测，跟着插件走。没写的项会 FAIL 并给出写法，不会默认放行。
# shellcheck shell=bash disable=SC2034
#
# vLLM：sso=proxy，网关给每个已登录请求注入 `Authorization: Bearer <api_key>`；
# vLLM 没有用户和登录体系（IDENTITY_NA=1），身份完全由核心网关的会话保证。
# 持久数据只有模型缓存（清单把模型放在数据目录的 models/ 子路径），装的过程
# 就验证了它落在数据目录，数据两项记 N/A；装不到旧版 tag 的场景由调用方 --no-upgrade 处理。
export IDENTITY_NA=1
export SMOKE_NOTE="vLLM 没有用户体系；持久数据只有模型缓存，数据两项记 N/A"

# / 的响应是插件根页：meta 跳转到 /docs，标题 vLLM；页面上没有 vllm 字样的
# JSON（那是 /version 接口）。用根页自身的特征断言身份；网关对匿名请求返回 401
# 由探针主干另行验证。
web_assert() {
  local page
  page="$(cat)"
  grep -q '<title>vLLM</title>' <<<"$page" && grep -q 'url=/docs' <<<"$page"
}

# 附加检查：经核心网关（SMOKE_WEB_URL）真调一次 /v1/chat/completions，确认真能推理、回的是中文。
# 网页只是接口文档页，不经核心网关直打容器端口不算。网关把 API key 注进已登录会话的请求
# （dweb 建会话），用 enable_thinking=false 免得思考内容把 max_tokens 吃光、content 为空。
extra_check() {
  local resp http_code body answer
  dweb --fresh / -L >/dev/null || { echo "核心/插件网页登不进，拿不到会话"; return 1; }
  # dweb 自身最多 240 秒，附加检查限 600 秒：这里的 --max-time 留到 340。
  resp="$(curl -sS --noproxy '*' --max-time 340 -b "$SMOKE_JAR" \
    -H 'Content-Type: application/json' \
    --data '{"model":"Qwen/Qwen3-8B","messages":[{"role":"user","content":"用一句中文说说你在做什么。"}],"max_tokens":512,"temperature":0,"chat_template_kwargs":{"enable_thinking":false}}' \
    -w '\n%{http_code}' \
    "$SMOKE_WEB_URL/v1/chat/completions")" ||
    { echo "请求 $SMOKE_WEB_URL/v1/chat/completions 没有响应（超时或连接失败）"; return 1; }
  http_code="${resp##*$'\n'}"
  body="${resp%$'\n'*}"
  [[ "$http_code" == 200 ]] ||
    { echo "HTTP $http_code：$(head -c 300 <<<"$body" | tr '\n' ' ')"; return 1; }
  answer="$(jq -r '.choices[0].message.content // ""' <<<"$body" 2>/dev/null)"
  [[ -n "$answer" ]] || { echo "回答为空：$(head -c 300 <<<"$body" | tr '\n' ' ')"; return 1; }
  grep -qP '[\x{4e00}-\x{9fff}]' <<<"$answer" ||
    { echo "回答里没有中文：$(head -c 300 <<<"$answer")"; return 1; }
  echo "模型回答（前 300 字）：$(head -c 300 <<<"$answer" | tr '\n' ' ')"
}

# 数据：应用不存用户数据时写 DATA_NA=1（升级/重装两项记 N/A）。vLLM 的模型缓存在数据目录的
# models/ 子路径，装好后即落到那里，下次启动不再下载；没有别的用户数据。
export DATA_NA=1
