# scripts/smoke.sh 的一项一项探测，跟着插件走。没写的项会 FAIL 并给出写法，不会默认放行。
# shellcheck shell=bash disable=SC2034
#（IDENTITY_NA、DATA_NA、SMOKE_NOTE 由套件 smoke.sh 读取，这里只赋值。）
# 钩子只准用白名单里的东西：SMOKE_STATE/SMOKE_JAR/SMOKE_WEB_URL/SMOKE_OWNER/
# SMOKE_BASE/SMOKE_TOKEN/SMOKE_INSTANCE 七个变量和 web_get、dweb 两个助手；
# 不读 E2E_*，不调套件内部函数。本文件只用到 web_get。
#
# vLLM：sso=proxy，网关给每个已登录请求注入 `Authorization: Bearer <api_key>`；
# vLLM 没有用户和登录体系（IDENTITY_NA=1），身份完全由核心网关的会话保证。
# vLLM 是无状态推理服务，不保存任何用户数据（DATA_NA=1）；数据目录里只有模型缓存，
# 属运行缓存而非用户数据，探针不验证。
IDENTITY_NA=1
DATA_NA=1
SMOKE_NOTE="vLLM 没有用户体系，也没有用户数据；模型缓存在数据目录，属运行缓存"

# / 的响应是反代跳到 /docs 的 Swagger 页，页面上没有 vllm 字样（FastAPI 默认标题）；
# 用 vLLM 自己的 /version 断言身份（经网关时密钥已由代登录注入）。
web_assert() {
  local v
  v="$(web_get /version)" || { echo "/version 请求失败：$v"; return 1; }
  grep -qE '"version"\s*:\s*"[0-9]+(\.[0-9]+)+"' <<<"$v" ||
    { echo "/version 响应不像 vLLM：$(head -c 120 <<<"$v")"; return 1; }
}
