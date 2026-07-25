# RDGen - RustDesk 自定义客户端生成器，搭配自托管 RustDesk 服务器使用

客户端生成器目前托管在[此处](https://rdgen.crayoneater.org)。
如果您想自行托管生成器，请参阅[这里](setup.md)

## 功能特性

- 将服务器地址和密钥嵌入客户端
- 自定义应用名称
- 自定义图标/Logo
- 设置客户端默认配置
- 支持 RustDesk 高级设置 (https://rustdesk.com/docs/en/self-host/client-configuration/advanced-settings/)

## 通过命令行生成 RustDesk 客户端（无需浏览器）

在 RDGen 网页界面保存配置，或自行生成配置，然后使用该 JSON 文件配合 [@AlekseyLapunov 的 rdgen-cli](https://github.com/AlekseyLapunov/rdgen-cli) 在 Windows、Linux 或 macOS 命令行中构建：`python rdgen-cli -f my_config.json --set-version 1.4.5 --set-platform windows -s https://rdgen.crayoneater.org`

## 注意事项

- 图标应为正方形（建议 256x256）
- 应用名称和文件名称中避免使用特殊字符或非英文字符
- 构建时间约为 30 到 45 分钟
