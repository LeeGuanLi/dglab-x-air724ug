# dglab-x-air724ug
air724ug短信转发联动dglab websocket

当收到指定短信时将控制dglab，如增大/减小/开始/停止/切换波形

本项目基于此项目的基础上添加了websocket功能，引用项目：https://github.com/0wQ/air724ug-forwarder

烧录流程请直接参考原项目链接，这里不重复描述。

dglab websocket使用方法：script/config.lua中找到 --websocket参数 这个注释，根据提示更改相关内容

详细参数配置：script/main.lua，找到-- dglab WebSocket配置

目前未开发完成且作者3.0没到货，先暂时搁置。等3.0到手再进一步测试（
