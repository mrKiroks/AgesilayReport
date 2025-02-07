require "lib.moonloader"
local samp = require 'lib.samp.events'
local json = require 'lib.json'
local encoding = require 'encoding'
encoding.default = 'CP1251'
local requests = require 'lib.requests' 


script_name("AgesilayReport")
script_version("0.8")

--�����������
local function log(message)
    local file = io.open(getWorkingDirectory() .. "\\agesilay_report.log", "a")
    if file then
        file:write(os.date("%Y-%m-%d %H:%M:%S") .. " - " .. message .. "\n")
        file:close()
    end
end


-- ������ �� ��������� Gist
local GIST_URL = "https://gist.githubusercontent.com/mrKiroks/790a17d1c015ccdba65d48eb3281e8b4/raw/"

local CHECK_INTERVAL = 5000 -- �������� ����� ��������� ������ 5 ������
local LAST_UPDATE_ID = 0

-- ���������� ��� ������������
local DISCORD_WEBHOOK, TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID

-- ���������� ��� ����������
local currentDay = os.date("%d")
local stats = {
    day = { invitations = {} },
    week = { invitations = {} },
    month = { invitations = {} }
}

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
    
    local url = string.format("https://api.telegram.org/bot%s/sendMessage", TELEGRAM_BOT_TOKEN)
    local payload = {
        chat_id = TELEGRAM_CHAT_ID,
        text = message
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
    -- �������� ��� ������, ������� ���������� �����
    local playerNickname = sampGetPlayerNickname(select(2, sampGetPlayerIdByCharHandle(playerPed)))

    -- ��������� ���������
    local message = "Daily Report:\n"
    message = message .. "Sent by: " .. playerNickname .. "\n\n"  -- ��������� ��� �����������
    if #stats.day.invitations == 0 then
        message = message .. "No Invites for the Day\n"
    else
        for _, invitation in ipairs(stats.day.invitations) do
            message = message .. string.format("- %s Invited %s\n", invitation.inviter, invitation.invitee)
        end
    end
    message = message .. "\nTotal for the Week: " .. #stats.week.invitations .. " invites\n"
    message = message .. "Total for the Month: " .. #stats.month.invitations .. " invites"
    
    -- ���������� ��������� � Discord � Telegram
    sendToDiscord(message)
    sendToTelegram(message)
    
    -- ������� ���������� �� ���� � ���������
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
	
	autoupdate("https://gist.githubusercontent.com/mrKiroks/94241347138c08c30a5e1fda7e9569c3/raw/9813a91f2464aeadb5cf848ca745ace2f248459a/AgesilayReportUptade", '['..string.upper(thisScript().name)..']: ', "https://github.com/mrKiroks/AgesilayReport")
    
	loadConfig()
    loadStats()

	lua_thread.create(checkTelegramUpdates)

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


local function checkTelegramUpdates()
    while true do
        wait(CHECK_INTERVAL)
        local url = string.format(
            "https://api.telegram.org/bot%s/getUpdates?offset=%d",
            TELEGRAM_BOT_TOKEN,
            LAST_UPDATE_ID + 1
        )
        
        local response = requests.get(url)
        if response and response.status_code == 200 then
            local data = json.decode(response.text)
            if data and data.result then
                for _, update in ipairs(data.result) do
                    LAST_UPDATE_ID = update.update_id
                    if update.message and update.message.text then
                        local text = update.message.text
                        local cmd, args = text:match("^/(%S+)%s*(.-)$")
                        if cmd then
                            processTelegramCommand(cmd, args)
                        end
                    end
                end
            end
        end
    end
end

local function processTelegramCommand(command, args)
    if command == "funinvite" and args then
        local nickname = args:match("^%s*(.-)%s*$")
        if nickname then
            local playerId = sampGetPlayerIdByNickname(nickname)
            if playerId ~= -1 then
                sampSendChat("/famunvinte " .. playerId)
                sendToTelegram("? Player "..nickname.." found! ID: "..playerId)
            else
                sampSendChat("/famoffkick " .. nickname)
                sendToTelegram("?? Player "..nickname.." not found on the server")
            end
        end
    end
end


function autoupdate(json_url, prefix, url)
  local dlstatus = require('moonloader').download_status
  local json = getWorkingDirectory() .. '\\'..thisScript().name..'-version.json'
  if doesFileExist(json) then os.remove(json) end
  downloadUrlToFile(json_url, json,
    function(id, status, p1, p2)
      if status == dlstatus.STATUSEX_ENDDOWNLOAD then
        if doesFileExist(json) then
          local f = io.open(json, 'r')
          if f then
            local info = decodeJson(f:read('*a'))
            updatelink = info.updateurl
            updateversion = info.latest
            f:close()
            os.remove(json)
            if updateversion ~= thisScript().version then
              lua_thread.create(function(prefix)
                local dlstatus = require('moonloader').download_status
                local color = -1
                sampAddChatMessage((prefix..'���������� ����������. ������� ���������� c '..thisScript().version..' �� '..updateversion), color)
                wait(250)
                downloadUrlToFile(updatelink, thisScript().path,
                  function(id3, status1, p13, p23)
                    if status1 == dlstatus.STATUS_DOWNLOADINGDATA then
                      print(string.format('��������� %d �� %d.', p13, p23))
                    elseif status1 == dlstatus.STATUS_ENDDOWNLOADDATA then
                      print('�������� ���������� ���������.')
                      sampAddChatMessage((prefix..'���������� ���������!'), color)
                      goupdatestatus = true
                      lua_thread.create(function() wait(500) thisScript():reload() end)
                    end
                    if status1 == dlstatus.STATUSEX_ENDDOWNLOAD then
                      if goupdatestatus == nil then
                        sampAddChatMessage((prefix..'���������� ������ ��������. �������� ���������� ������..'), color)
                        update = false
                      end
                    end
                  end
                )
                end, prefix
              )
            else
              update = false
              print('v'..thisScript().version..': ���������� �� ���������.')
            end
          end
        else
          print('v'..thisScript().version..': �� ���� ��������� ����������. ��������� ��� ��������� �������������� �� '..url)
          update = false
        end
      end
    end
  )
  while update ~= false do wait(100) end
end