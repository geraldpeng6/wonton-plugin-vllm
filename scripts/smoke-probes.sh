# scripts/smoke.sh 的一项一项探测，跟着插件走。没写的项会 FAIL 并给出写法，不会默认放行。
# shellcheck shell=bash disable=SC2034
#（IDENTITY_NA、DATA_NA、SMOKE_NOTE 由套件 smoke.sh 读取，这里只赋值。）
#
# vLLM：sso=proxy，网关给每个已登录请求注入 `Authorization: Bearer <api_key>`；
# vLLM 没有用户和登录体系（IDENTITY_NA=1），身份完全由核心网关的会话保证。
# vLLM 是无状态推理服务，不保存任何用户数据（DATA_NA=1）；数据目录里只有模型缓存，
# 属运行缓存而非用户数据，探针不验证。
IDENTITY_NA=1
DATA_NA=1
SMOKE_NOTE="vLLM 没有用户体系，也没有用户数据；模型缓存在数据目录，属运行缓存"

web_assert() { grep -qi 'vllm'; }   # 标准输入：经网关打开的应用页面
