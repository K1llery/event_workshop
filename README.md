# 以撒事件工坊

面向《以撒的结合：忏悔+》的单人事件规则模组，使用原版 Lua API，通过 Mod Config Menu 和游戏控制台配置。

支持清房、进房、进层、开局、伤害、敌人死亡和主动使用事件；条件可设置概率、每 N 次、房间/角色/持有道具，以及每房间/层/局执行上限。动作可生成底座或掉落物、给予道具、调整资源/生命/充能、生成敌人；多动作按顺序执行。

新局自动关闭总开关，配置保留；继续游戏恢复该局状态。首次手动启用只执行一次开局规则，不更改种子或重开游戏。

- 模组源码：[event_workshop](event_workshop)
- 中文操作说明与控制台示例：[使用说明](docs/使用说明.md)
- 验证：python3 tools/check.py
- 安装并打包：python3 tools/deploy.py

本项目不依赖 MCM 的保存功能，使用模组自身的 SaveData 保存配置及局内状态。默认示例规则均禁用。

忏悔+ 原生控制台入口：`lua EW("help")`、`lua EW("status")`。触发事件在 MCM“条件”页设置。

创意工坊发布素材位于 [workshop](workshop)。运行 `python3 tools/prepare_workshop.py` 可生成独立的隐藏上传目录；操作步骤见 [上传步骤](workshop/上传步骤.md)。已有创意工坊条目 ID 与上传修订号会保留。
