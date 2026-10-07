# 以撒事件工坊

面向《以撒的结合：忏悔+》的单人事件规则模组，使用原版 Lua API，通过 Mod Config Menu 和游戏控制台配置。

1.1.0 提供 90 种事件入口、102 类参数化动作、完整原版枚举目录与条件筛选，MCM 按分类编辑，并提供执行记录。规则允许正常联动；同一因果链中每条规则最多执行一次，配合事件、动作和生成数量限流，防止自循环和相互循环。完整功能与限制见 [覆盖清单](docs/覆盖清单.md)。

新局自动关闭总开关，配置保留；继续游戏恢复该局状态。首次手动启用只执行一次开局规则，不更改种子或重开游戏。

- 模组源码：[event_workshop](event_workshop)
- 中文操作说明与控制台示例：[使用说明](docs/使用说明.md)
- 验证：python3 tools/check.py
- 安装并打包：python3 tools/deploy.py

本项目不依赖 MCM 的保存功能，使用模组自身的 SaveData 保存配置及局内状态。默认示例规则均禁用。

忏悔+ 原生控制台入口：`lua EW("help")`、`lua EW("status")`。触发事件在 MCM“条件”页设置。

创意工坊发布素材位于 [workshop](workshop)。运行 `python3 tools/prepare_workshop.py` 可生成独立的隐藏上传目录；操作步骤见 [上传步骤](workshop/上传步骤.md)。已有创意工坊条目 ID 与上传修订号会保留。
