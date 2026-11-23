# 双人联机施法演示

练习场通过主机结算指定目标技能。两个玩家各有自己的 Mana、施法状态和冷却。目标由主机按距离、阵营和存活状态复核，标记也由主机推进到期。

已有的 RoomLobby 地图另外提供双机玩法，支持宿主生成来宾角色、同步移动和在同一大厅重连。 [RoomLobby 双机 LAN 运行和验收](LAN.md)

## 运行和试玩

准备 Git、Python 3.10+、Godot 4.7.2，以及包含正式插件 `4e85c03` 的 Git 检出。以下命令从 Ability Demo 根目录运行，Windows 可使用 Godot 控制台版。启动器从指定提交归档插件，将其装入临时工程，并在本机回环地址启动两个进程。主演示可以继续从仓库根目录的 `project.godot` 运行。 [正式插件](https://github.com/LiGameAcademy/godot_gameplay_abilities)

```powershell
python tests/run_multiplayer_cast.py --godot "<Godot 可执行文件>" --plugin "<正式插件检出路径>" --play
```

- 主机窗口控制 1 号，客户端窗口控制 2 号。3 号是与 1 号同阵营的练习目标。
- 在任一窗口按 1、2 或 3 选择目标，按 Enter 或空格施法。主机可攻击 2 号，客户端可在 1 号和 3 号之间选择。
- 实体行显示 `Windup`、`Cooldown` 或 `Ready`。目标的 `Marked` 独立显示，可与任一施法阶段共存。
- 客户端按 R 断线，再按 R 连回同一主机。重连后窗口显示各实体的当前 Mana、冷却和标记。
- 关闭任一窗口结束，或在终端按 Ctrl+C。端口占用时可追加 `--port <UDP 端口>`。

移除 `--play` 即运行自动验收。失败时终端输出对应主机与客户端日志。 [验收用例](../tests/README.md)

## 从输入到结算

| 文件 | 职责 |
| --- | --- |
| [cast_demo.gd](cast_demo.gd) | 维护连接代次和控制者映射。主机按连接身份决定施法者，本地和远端输入共用提交入口。发布单次回执与版本化的实体快照。 |
| [cast_request_ledger.gd](cast_request_ledger.gd) | 每个控制者保留自己的请求记录。重发回放已有回执，活跃请求的记录保留到结算结束。 |
| [cast_arena.tscn](cast_arena.tscn) 和 [cast_arena.gd](cast_arena.gd) | 主机的练习场。配置实体、阵营和初始位置，解析指定目标，在受理和提交前检查实体及距离。 |
| [cast_rules.tscn](cast_rules.tscn) 和 [cast_rules.gd](cast_rules.gd) | 每个实体独立持有 Ability、Vital、Status 组件。调用正式插件的 `TargetedStatusAbilityDefinition`，读取 `Cast.result` 并发出结算信号。 |

回执关联会话与请求号，表达受理、拒绝或结束。前摇占用、冷却和起手时费用不足分别返回 `BUSY`、`COOLDOWN` 和 `INSUFFICIENT_MANA`。前摇后的 `PAYMENT_FAILED` 或 `TARGET_INVALID` 保留结算前的费用、冷却和状态。若返回 `STATUS_NOT_APPLIED`，已提交的费用和冷却仍然生效。

快照以实体 ID 为键，包含 Mana、施法是否活动、冷却是否生效、标记和练习场实体数据。客户端按版本更新展示，权威写入发生在主机。目标身上的标记由它的 Status 组件计时，施法者在自己的冷却结束后可以再选目标。首次加入和重连从实时快照恢复，离场实体从下一份快照移除。

## 宿主接入范围

本演示验证同一主机进程加一个远端玩家、一个技能、练习场目标和回环连接。正式插件负责局部施法和结算，宿主负责角色归属、实体生命周期、传输、快照路由和场景同步。当前的实体快照覆盖练习场所需字段。完整游戏的玩家移动复制、跨场景切换、正式部署、预测与主机迁移留待宿主扩展。
