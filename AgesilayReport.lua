require "lib.moonloader"
local samp = require 'lib.samp.events'
local json = require 'lib.json'
local encoding = require 'encoding'
encoding.default = 'CP1251'
local requests = require 'lib.requests'

-- ������ �� ��������� Gist
local GIST_URL = "https://gist.githubusercontent.com/mrKiroks/790a17d1c015ccdba65d48eb3281e8b4/raw/"

-- ���������� ��� ������������
local DISCORD_WEBHOOK, TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID

-- ���������� ��� ����������
local currentDay = os.date("%d")
local stats = {
    day = { invitations = {} },
    week = { invitations = {} },
    month = { invitations = {} }
}

-- �����������
local function log(message)
    local file = io.open(getWorkingDirectory() .. "\\agesilay_report.log", "a")
    if file then
        file:write(os.date("%Y-%m-%d %H:%M:%S") .. " - " .. message .. "\n")
        file:close()
    end
end

-- �������� ������������
local function loadConfig()
    local success, response = pcall(requests.get, GIST_URL)
    if success and response and response.status_code == 200 then
        local config = json.decode(response.text)
        if config then
            DISCORD_WEBHOOK = config.discord_webhook or nil
            TELEGRAM_BOT_TOKEN = config.telegram_bot_token or nil
            TELEGRAM_CHAT_ID = config.telegram_chat_id or nil
            sampAddChatMessage("{6B21BB}[AgesilayReport]{FFFFFF} ������������ ���������!", 0xFFFFFF)
            log("������������ ���������: " .. json.encode(config))
        else
            sampAddChatMessage("{FF0000}[AgesilayReport]{FFFFFF} ������ ������������� ������������!", 0xFFFFFF)
            log("������ ������������� ������������. ����� �������: " .. (response.text or "nil"))
        end
    else
        local err = "������ �������� ������������: "
        if not success then err = err .. tostring(response)
        else err = err .. " HTTP " .. (response.status_code or "��� ������") end
        sampAddChatMessage("{FF0000}[AgesilayReport]{FFFFFF} " .. err, 0xFFFFFF)
        log(err)
    end
end

-- �������� ����������
local function loadStats()
    local file = io.open(getWorkingDirectory() .. "\\family_stats.json", "r")
    if file then
        local content = file:read("*a")
        file:close()
        stats = json.decode(content) or stats
        log("���������� ���������: " .. #stats.day.invitations .. " ������� �������")
    else
        log("���� ���������� �� ������, ������ �����")
    end
end

-- ���������� ����������
local function saveStats()
    local file = io.open(getWorkingDirectory() .. "\\family_stats.json", "w")
    if file then
        file:write(json.encode(stats))
        file:close()
        log("���������� ���������: " .. #stats.day.invitations .. " ������� �������")
    else
        log("������ ���������� ����������!")
    end
end

-- �������� � Discord
local function sendToDiscord(message)
    if not DISCORD_WEBHOOK then return end
    local payload = {
        content = message
    }
    local response = requests.post(DISCORD_WEBHOOK, {
        headers = { ["Content-Type"] = "application/json" },
        data = json.encode(payload)
    })
    if response and response.status_code == 204 then
        log("��������� ���������� � Discord")
    else
        log("������ �������� � Discord: " .. (response.status_code or "��� ������"))
    end
end

-- �������� � Telegram
local function sendToTelegram(message)
    if not TELEGRAM_BOT_TOKEN or not TELEGRAM_CHAT_ID then 
        log("�� ������� Telegram ����� ��� chat ID")
        return 
    end
    
    -- ����������� ��������� � UTF-8
    local utf8_message = encoding.convert(message, "UTF-8", "CP1251")
    
    local url = string.format("https://api.telegram.org/bot%s/sendMessage", TELEGRAM_BOT_TOKEN)
    local payload = {
        chat_id = TELEGRAM_CHAT_ID,
        text = utf8_message
    }
    local response = requests.post(url, {
        headers = { ["Content-Type"] = "application/json" },
        data = json.encode(payload)
    })
    
    if response and response.status_code == 200 then
        log("��������� ���������� � Telegram")
    else
        local err = "������ �������� � Telegram: "
        if response then
            err = err .. response.status_code .. " - " .. (json.decode(response.text).description or "����������� ������")
        else
            err = err .. "��� ������"
        end
        log(err)
    end
end

-- ��������� ���������
function samp.onServerMessage(color, text)
    -- ������� �������� ���� ��� ��������� ������
    local cleanText = text:gsub("{......}", "")
    
    if cleanText:find("%[����� %(�������%)%]") and cleanText:find("��������� � ����� ������ �����:") then
        local inviter, invitee = cleanText:match("%[����� %(�������%)%] ([%w_%[%]%d]+): ��������� � ����� ������ �����: ([%w_%[%]%d]+)!")
        if inviter and invitee then
            table.insert(stats.day.invitations, { inviter = inviter, invitee = invitee, timestamp = os.time() })
            table.insert(stats.week.invitations, { inviter = inviter, invitee = invitee, timestamp = os.time() })
            table.insert(stats.month.invitations, { inviter = inviter, invitee = invitee, timestamp = os.time() })
            saveStats()
            log("��������� �����������: " .. inviter .. " -> " .. invitee)
        else
            log("�� ������� ���������� ���������: " .. cleanText)
        end
    end
end

-- �������� ����������� ������
local function sendDailyReport()
    local message = "?? ����� �� ����:\n"
    if #stats.day.invitations == 0 then
        message = message .. "��� ����������� �� ����\n"
    else
        for _, invitation in ipairs(stats.day.invitations) do
            message = message .. string.format("- %s ��������� %s\n", invitation.inviter, invitation.invitee)
        end
    end
    message = message .. "\n?? ����� �� ������: " .. #stats.week.invitations .. " �����������\n"
    message = message .. "?? ����� �� �����: " .. #stats.month.invitations .. " �����������"
    
    sendToTelegram(message)
    stats.day.invitations = {}
    saveStats()
    log("��������� ���������� �����")
end

-- �������� �������
function main()
    if not isSampfuncsLoaded() or not isSampLoaded() then
        return
    end
    while not isSampAvailable() do
        wait(100)
    end

    sampAddChatMessage("{6B21BB}[AgesilayReport]{FFFFFF} ������ �����������, ����� - {6B21BB}Kiroks{FFFFFF}.", 0xFFFFFF)
    log("������ �����������")

    loadConfig()
    loadStats()

    local lastCheckDay = currentDay
    while true do	
        wait(0)
        local newDay = os.date("%d")
        if newDay ~= lastCheckDay then
            log("���������� ����� ���: " .. lastCheckDay .. " -> " .. newDay)
            sendDailyReport()
            lastCheckDay = newDay
            -- ��������� ���������� ��� ����� ���
            loadStats()
        end
    end
end