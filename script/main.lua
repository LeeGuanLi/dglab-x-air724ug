PROJECT = "air724ug-forwarder"
VERSION = "1.0.0"

require "log"
LOG_LEVEL = log.LOGLEVEL_INFO
require "config"
require "nvm"
nvm.init("config.lua")
require "audio"
audio.setStrategy(1)
require "cc"
require "common"
require "http"
require "misc"
require "net"
require "netLed"
require "ntp"
require "powerKey"
require "record"
require "ril"
require "sim"
require "sms"
require "sys"
require "util_mobile"
require "util_audio"
require "util_http"
require "util_notify"
require "util_temperature"
require "util_ntp"
require "handler_call"
require "handler_powerkey"
require "handler_sms"
require "usbmsc"

-- 输出音频通道选项, 0:听筒 1:耳机 2:喇叭
-- 输入音频通道选项, 0:main_mic 1:auxiliary_mic 3:headphone_mic_left 4:headphone_mic_right

-- 静音音频通道
AUDIO_OUTPUT_CHANNEL_MUTE = 0
AUDIO_INPUT_CHANNEL_MUTE = 1
-- 正常音频通道
AUDIO_OUTPUT_CHANNEL_NORMAL = 2
AUDIO_INPUT_CHANNEL_NORMAL = 0

audio.setChannel(AUDIO_OUTPUT_CHANNEL_NORMAL, AUDIO_INPUT_CHANNEL_NORMAL)

-- 配置内部 PA 类型 audiocore.CLASS_AB, audiocore.CLASS_D
audiocore.setpa(audiocore.CLASS_D)
-- 配置外部 PA
-- pins.setup(pio.P0_14, 0)
-- audiocore.pa(pio.P0_14, 1, 0, 0)
-- audio.setChannel(1)

-- 设置睡眠等待时间
-- ril.request("AT+WAKETIM=0")

-- 定时查询温度
sys.timerLoopStart(util_temperature.get, 1000 * 60)
-- 定时查询 信号强度 基站信息
net.startQueryAll(1000 * 60, 1000 * 60 * 10)

-- RNDIS
ril.request("AT+RNDISCALL=" .. (nvm.get("RNDIS_ENABLE") and 1 or 0) .. ",0")

-- NET 指示灯, LTE 指示灯
if nvm.get("LED_ENABLE") then
    pmd.ldoset(2, pmd.LDO_VLCD)
end
netLed.setup(true, pio.P0_1, pio.P0_4)
netLed.updateBlinkTime("SCK", 50, 50)
netLed.updateBlinkTime("GPRS", 200, 2000)

-- 开机查询本机号码
sim.setQueryNumber(true)
sys.timerStart(ril.request, 3000, "AT+CNUM")
-- 如果查询不到本机号码, 可以取消下面注释的代码, 尝试手动写入到 SIM 卡, 写入成功后注释掉即可
 --sys.timerStart(ril.request, 5000, 'AT+CPBS="ON"')
 --sys.timerStart(ril.request, 6000, 'AT+CPBW=1,"+8613111111111",145')

-- SIM 自动切换开关
ril.request("AT*SIMAUTO=1")

-- SIM 热插拔
pins.setup(23, function(msg)
    if msg == cpu.INT_GPIO_POSEDGE then
        log.info("SIM_DETECT", "插卡")
        rtos.notify_sim_detect(1, 1)
        -- 查询本机号码
        sys.timerStart(ril.request, 1000, "AT+CNUM")
        -- 发送插卡通知
        sys.timerStart(util_notify.add, 2000, "#SIM_INSERT")
    else
        log.info("SIM_DETECT", "拔卡")
        rtos.notify_sim_detect(1, 0)
    end
end, pio.PULLDOWM)

sys.taskInit(function()
    -- 等待网络就绪
    sys.waitUntil("IP_READY_IND", 1000 * 60 * 2)

    -- 等待获取 Band 值
    -- sys.wait(1000 * 5)

    -- 开机通知
    if nvm.get("BOOT_NOTIFY") then
        util_notify.add("#BOOT_" .. rtos.poweron_reason())
    end

    -- 定时查询流量
    if config.QUERY_TRAFFIC_INTERVAL and config.QUERY_TRAFFIC_INTERVAL >= 1000 * 60 then
        sys.timerLoopStart(util_mobile.queryTraffic, config.QUERY_TRAFFIC_INTERVAL)
    end

    -- 开机同步时间
    util_ntp.sync()
    sys.timerLoopStart(util_ntp.sync, 1000 * 30)
end)




-- dglab WebSocket配置
local websocket = require("websocket")
local json = require("json")

-- 初始化WebSocket连接
local function init_websocket()
    local ws = websocket.client.sync()
    local ok, err = ws:connect(websocket_config.server_url)
    if not ok then
        print("WebSocket连接失败: ", err)
    end
    return ws
end

-- 发送WebSocket消息
local function send_websocket_message(ws, message)
    if ws then
        local ok, err = ws:send(json.encode(message))
        if not ok then
            print("WebSocket消息发送失败: ", err)
        end
    end
end

-- 解析短信内容为命令
local function parse_message_to_command(message)
    local command = {}
    if string.find(message:lower(), "开始电击a") then
        command = {
            type = "msg",
            clientId = websocket_config.clientId,
            targetId = websocket_config.targetId,
            message = "strength-1+2+5"  -- 示例：设定A通道强度为5
        }
    elseif string.find(message:lower(), "停止电击a") then
        command = {
            type = "msg",
            clientId = websocket_config.clientId,
            targetId = websocket_config.targetId,
            message = "strength-1+2+0"  -- 示例：设定A通道强度为0
        }
    elseif string.find(message:lower(), "强度增加a") then
        local n = tonumber(string.match(message, "%d+"))
        if n then
            command = {
                type = "msg",
                clientId = websocket_config.clientId,
                targetId = websocket_config.targetId,
                message = "strength-1+1+" .. tostring(n)  -- 增加A通道强度
            }
        end
    elseif string.find(message:lower(), "强度减少a") then
        local n = tonumber(string.match(message, "%d+"))
        if n then
            command = {
                type = "msg",
                clientId = websocket_config.clientId,
                targetId = websocket_config.targetId,
                message = "strength-1+0+" .. tostring(n)  -- 减少A通道强度
            }
        end
    elseif string.find(message:lower(), "切换波形a") then
        command = {
            type = "msg",
            clientId = websocket_config.clientId,
            targetId = websocket_config.targetId,
            message = "pulse-1:[\"0011223344556677\", \"8899aabbccddeeff\"]"  -- 示例：波形数据
        }
    elseif string.find(message:lower(), "开始电击b") then
        command = {
            type = "msg",
            clientId = websocket_config.clientId,
            targetId = websocket_config.targetId,
            message = "strength-2+2+5"  -- 示例：设定B通道强度为5
        }
    elseif string.find(message:lower(), "停止电击b") then
        command = {
            type = "msg",
            clientId = websocket_config.clientId,
            targetId = websocket_config.targetId,
            message = "strength-2+2+0"  -- 示例：设定B通道强度为0
        }
    elseif string.find(message:lower(), "强度增加b") then
        local n = tonumber(string.match(message, "%d+"))
        if n then
            command = {
                type = "msg",
                clientId = websocket_config.clientId,
                targetId = websocket_config.targetId,
                message = "strength-2+1+" .. tostring(n)  -- 增加B通道强度
            }
        end
    elseif string.find(message:lower(), "强度减少b") then
        local n = tonumber(string.match(message, "%d+"))
        if n then
            command = {
                type = "msg",
                clientId = websocket_config.clientId,
                targetId = websocket_config.targetId,
                message = "strength-2+0+" .. tostring(n)  -- 减少B通道强度
            }
        end
    elseif string.find(message:lower(), "切换波形b") then
        command = {
            type = "msg",
            clientId = websocket_config.clientId,
            targetId = websocket_config.targetId,
            message = "pulse-2:[\"0011223344556677\", \"8899aabbccddeeff\"]"  -- 示例：波形数据
        }
    end
    return command
end

-- 当收到短信时调用
local function on_sms_received(number, message)
    print("收到短信来自: " .. number .. " 内容: " .. message)
    
    -- 解析短信内容并发送WebSocket消息
    local command = parse_message_to_command(message)
    if command then
        -- 初始化WebSocket
        local ws = init_websocket()
        if ws then
            send_websocket_message(ws, command)
            -- 关闭WebSocket连接
            ws:close()
        end
    else
        print("无法解析短信内容，未触发WebSocket")
    end
end

-- 初始化SMS接收
sms.init(on_sms_received)
----websocket结束



-- 系统初始化
sys.init(0, 0)
sys.run()
