require "lib.moonloader"
local samp = require 'lib.samp.events'
local json = require 'lib.json'
local encoding = require 'encoding'
encoding.default = 'CP1251'
local requests = require 'lib.requests'

-- Ссылка на приватный Gist
local GIST_URL = "https://gist.githubusercontent.com/mrKiroks/790a17d1c015ccdba65d48eb3281e8b4/raw/"

-- Переменные для конфигурации
local DISCORD_WEBHOOK, TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID

-- Переменные для статистики
local currentDay = os.date("%d")
local stats = {
    day = { invitations = {} },
    week = { invitations = {} },
    month = { invitations = {} }
}

-- Логирование
local function log(message)
    local file = io.open(getWorkingDirectory() .. "\\agesilay_report.log", "a")
    if file then
        file:write(os.date("%Y-%m-%d %H:%M:%S") .. " - " .. message .. "\n")
        file:close()
    end
end

-- Загрузка конфигурации
local function loadConfig()
    local success, response = pcall(requests.get, GIST_URL)
    if success and response and response.status_code == 200 then
        local config = json.decode(response.text)
        if config then
            DISCORD_WEBHOOK = config.discord_webhook or nil
            TELEGRAM_BOT_TOKEN = config.telegram_bot_token or nil
            TELEGRAM_CHAT_ID = config.telegram_chat_id or nil
            sampAddChatMessage("{6B21BB}[AgesilayReport]{FFFFFF} Конфигурация загружена!", 0xFFFFFF)
            log("Конфигурация загружена: " .. json.encode(config))
        else
            sampAddChatMessage("{FF0000}[AgesilayReport]{FFFFFF} Ошибка декодирования конфигурации!", 0xFFFFFF)
            log("Ошибка декодирования конфигурации. Ответ сервера: " .. (response.text or "nil"))
        end
    else
        local err = "Ошибка загрузки конфигурации: "
        if not success then err = err .. tostring(response)
        else err = err .. " HTTP " .. (response.status_code or "нет ответа") end
        sampAddChatMessage("{FF0000}[AgesilayReport]{FFFFFF} " .. err, 0xFFFFFF)
        log(err)
    end
end

-- Загрузка статистики
local function loadStats()
    local file = io.open(getWorkingDirectory() .. "\\family_stats.json", "r")
    if file then
        local content = file:read("*a")
        file:close()
        stats = json.decode(content) or stats
        log("Статистика загружена: " .. #stats.day.invitations .. " дневных записей")
    else
        log("Файл статистики не найден, создан новый")
    end
end

-- Сохранение статистики
local function saveStats()
    local file = io.open(getWorkingDirectory() .. "\\family_stats.json", "w")
    if file then
        file:write(json.encode(stats))
        file:close()
        log("Статистика сохранена: " .. #stats.day.invitations .. " дневных записей")
    else
        log("Ошибка сохранения статистики!")
    end
end

-- Отправка в Discord
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
        log("Сообщение отправлено в Discord")
    else
        log("Ошибка отправки в Discord: " .. (response.status_code or "нет ответа"))
    end
end

-- Отправка в Telegram
local function sendToTelegram(message)
    if not TELEGRAM_BOT_TOKEN or not TELEGRAM_CHAT_ID then 
        log("Не указаны Telegram токен или chat ID")
        return 
    end
    
    -- Преобразуем сообщение в UTF-8
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
        log("Сообщение отправлено в Telegram")
    else
        local err = "Ошибка отправки в Telegram: "
        if response then
            err = err .. response.status_code .. " - " .. (json.decode(response.text).description or "неизвестная ошибка")
        else
            err = err .. "нет ответа"
        end
        log(err)
    end
end

-- Обработка сообщений
function samp.onServerMessage(color, text)
    -- Убираем цветовые коды для обработки текста
    local cleanText = text:gsub("{......}", "")
    
    if cleanText:find("%[Семья %(Новости%)%]") and cleanText:find("пригласил в семью нового члена:") then
        local inviter, invitee = cleanText:match("%[Семья %(Новости%)%] ([%w_%[%]%d]+): пригласил в семью нового члена: ([%w_%[%]%d]+)!")
        if inviter and invitee then
            table.insert(stats.day.invitations, { inviter = inviter, invitee = invitee, timestamp = os.time() })
            table.insert(stats.week.invitations, { inviter = inviter, invitee = invitee, timestamp = os.time() })
            table.insert(stats.month.invitations, { inviter = inviter, invitee = invitee, timestamp = os.time() })
            saveStats()
            log("Добавлено приглашение: " .. inviter .. " -> " .. invitee)
        else
            log("Не удалось распарсить сообщение: " .. cleanText)
        end
    end
end

-- Отправка ежедневного отчета
local function sendDailyReport()
    local message = "?? Отчет за день:\n"
    if #stats.day.invitations == 0 then
        message = message .. "Нет приглашений за день\n"
    else
        for _, invitation in ipairs(stats.day.invitations) do
            message = message .. string.format("- %s пригласил %s\n", invitation.inviter, invitation.invitee)
        end
    end
    message = message .. "\n?? Итого за неделю: " .. #stats.week.invitations .. " приглашений\n"
    message = message .. "?? Итого за месяц: " .. #stats.month.invitations .. " приглашений"
    
    sendToTelegram(message)
    stats.day.invitations = {}
    saveStats()
    log("Отправлен ежедневный отчет")
end

-- Основная функция
function main()
    if not isSampfuncsLoaded() or not isSampLoaded() then
        return
    end
    while not isSampAvailable() do
        wait(100)
    end

    sampAddChatMessage("{6B21BB}[AgesilayReport]{FFFFFF} Скрипт активирован, автор - {6B21BB}Kiroks{FFFFFF}.", 0xFFFFFF)
    log("Скрипт активирован")

    loadConfig()
    loadStats()

    local lastCheckDay = currentDay
    while true do	
        wait(0)
        local newDay = os.date("%d")
        if newDay ~= lastCheckDay then
            log("Обнаружена смена дня: " .. lastCheckDay .. " -> " .. newDay)
            sendDailyReport()
            lastCheckDay = newDay
            -- Обновляем статистику при смене дня
            loadStats()
        end
    end
end