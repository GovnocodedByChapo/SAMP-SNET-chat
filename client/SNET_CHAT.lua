script_name('S:NET Chat');
script_author('chapo', 'neverlane')

local ffi = require('ffi');
local inicfg = require('inicfg');
local directIni = 'SNetChat.ini';
local ini = inicfg.load({main = { login = '', password = '', autologin = false }}, directIni);
inicfg.save(ini, directIni);
local imgui = require('mimgui');
local snet = require('snet');
local SNetClient, bstream = snet.client('127.0.0.1', 11321), snet.bstream;
local Packet = {
    Ping = 0,
    Pong = 1,
    Registration = 2,
    RegistrationResponse = 3,
    Login = 4,
    LoginResponse = 5,
    SendMessage = 6,
    NewMessage = 7,
    UserJoin = 8,
    UserQuit = 9
};
local Page = {
    Registration = 0,
    Login = 1,
    Chat = 2
};
local input = {
    login = imgui.new.char[32](''),
    password = imgui.new.char[32](''),
    chat = imgui.new.char[128]('')
};
local loggedIn, myLogin, page, chat = false, 'NONE', Page.Login, {};
local renderWindow = imgui.new.bool(false);

SNetClient:add_event_handler('onReceivePacket', function(id, bs) 
    if (id == Packet.RegistrationResponse or id == Packet.LoginResponse) then
        local status = bs:read(BS_BOOLEAN);
        sampAddChatMessage('status '..tostring(status), -1)
        local login = bs:read(BS_STRING, bs:read(BS_INT16));
        local password = bs:read(BS_STRING, bs:read(BS_INT16));
        if (page == Page.Registration or page == Page.Login) then
            sampAddChatMessage(status and (id == Packet.LoginResponse and 'Вы успешно авторизовались!' or 'Регистрация прошла успешно!') or (id == Packet.LoginResponse and 'Ошибка, такой аккаунт не найден или пароль неверен' or 'Ошибка, такой пользователь уже зарегестрирован или пароль слишком короткий'), -1)
            if (status) then
                ini.main.login = login;
                ini.main.password = password;
                loggedIn, myLogin, page = true, login, Page.Chat;

                --// send join notification
                local bs = bstream.new();
                bs:write(BS_INT16, #login)
                bs:write(BS_STRING, login)
                SNetClient:send(Packet.UserJoin, bs, SNET_SYSTEM_PRIORITY)
            else
                page = Page.Login;
                renderWindow[0] = true;
            end
            ini.main.autologin = status
            inicfg.save(ini, directIni);
        end
    elseif (id == Packet.NewMessage) then
        local text = bs:read(BS_STRING, bs:read(BS_INT32));
        local sender = bs:read(BS_STRING, bs:read(BS_INT16));
        local timestamp = bs:read(BS_INT32);
        local dontAddToChat = bs:read(BS_BOOLEAN);
        table.insert(chat, {
            text = text,
            sender = sender,
            timestamp = timestamp
        });
        if (dontAddToChat) then return end
        sampAddChatMessage(('S:Chat > %s: %s'):format(sender, text), -1);
    elseif (id == Packet.UserJoin or id == Packet.UserQuit) then
        local name = bs:read(BS_STRING, bs:read(BS_INT16));
        sampAddChatMessage('SC > (system) user '..(id == Packet.UserJoin and 'join' or 'quit')..': '..name, -1);
    end
end)

addEventHandler('onScriptTerminate', function(scr, quitGame)
    if (scr == thisScript() and loggedIn) then
        local bs = bstream.new();
        bs:write(BS_INT16, #myLogin);
        bs:write(BS_STRING, myLogin);
        SNetClient:send(Packet.UserQuit, bs, SNET_SYSTEM_PRIORITY)
    end
end)

function sendMessage(msg)
    if not loggedIn then
        return sampAddChatMessage('S:Chat > (system) Error, you are not logged in! Use /schat to log in', -1)
    end
    local bs = bstream.new();
    bs:write(BS_INT32, #msg);
    bs:write(BS_STRING, msg);
    bs:write(BS_INT16, #myLogin);
    bs:write(BS_STRING, myLogin);
    bs:write(BS_INT32, os.time());
    bs:write(BS_BOOLEAN, false);
    SNetClient:send(Packet.SendMessage, bs, SNET_SYSTEM_PRIORITY);
end

function main()
    while not isSampAvailable() do wait(0) end
    sampRegisterChatCommand('sc', sendMessage);
    sampRegisterChatCommand('schat', function()
        renderWindow[0] = not renderWindow[0];
    end);
    
    if (ini.main.autologin) then
        local bs = bstream.new();
        --// login
        bs:write(BS_INT16, #ini.main.login);
        bs:write(BS_STRING, ini.main.login);
        --// password
        bs:write(BS_INT16, #ini.main.password);
        bs:write(BS_STRING, ini.main.password);
        SNetClient:send(Packet.Login, bs, SNET_SYSTEM_PRIORITY);
    end

    while true do
        wait(0);
        SNetClient:process();
    end
end

imgui.OnInitialize(function()
    imgui.GetStyle().WindowPadding = imgui.ImVec2(5, 5);
end)

local newFrame = imgui.OnFrame(
    function() return renderWindow[0] end,
    function(this)
        local res, size = imgui.ImVec2(getScreenResolution()), imgui.ImVec2(300, 300);
        imgui.SetNextWindowPos(imgui.ImVec2(res.x / 2, res.y / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5));
        imgui.SetNextWindowSize(page == Page.Chat and size or imgui.ImVec2(300, 160), page == Page.Chat and imgui.Cond.FirstUseEver or imgui.Cond.Always);
        if imgui.Begin('S:NET Chat', renderWindow, (page == Page.Chat and 0 or imgui.WindowFlags.NoResize)) then
            local size = imgui.GetWindowSize();
            if (page == Page.Registration or page == Page.Login) then
                local loginPage = page == Page.Login;
                imgui.CenterText(loginPage and 'LOGIN' or 'REGISTRATION');
                imgui.PushItemWidth(size.x - 10);
                imgui.InputText('##login', input.login, ffi.sizeof(input.login));
                imgui.InputText('##password', input.password, ffi.sizeof(input.password), imgui.InputTextFlags.Password);
                imgui.PopItemWidth();
                imgui.NewLine();

                if (imgui.Button(loginPage and 'Log in' or 'Create account', imgui.ImVec2(size.x - 10, 20))) then
                    local bs = bstream.new();
                    --// login
                    bs:write(BS_INT16, #ffi.string(input.login));
                    bs:write(BS_STRING, ffi.string(input.login));
                    --// password
                    bs:write(BS_INT16, #ffi.string(input.password));
                    bs:write(BS_STRING, ffi.string(input.password));
                    SNetClient:send(loginPage and Packet.Login or Packet.Registration, bs, SNET_SYSTEM_PRIORITY);
                end
                
                if (imgui.Button(loginPage and 'Create new account' or '<- Back to login', imgui.ImVec2(size.x - 10, 20))) then
                    page = loginPage and Page.Registration or Page.Login;
                    imgui.StrCopy(input.login, '');
                    imgui.StrCopy(input.password, '');
                end
            elseif (page == Page.Chat) then
                if (imgui.Button('Log Out')) then
                    loggedIn = false;
                    page = Page.Login;
                end
                imgui.SameLine();
                imgui.Text('Logged in as '..myLogin);
                imgui.SetCursorPosY(50);
                if imgui.BeginChild('chat', imgui.ImVec2(size.x - 10, size.y - 80), true) then
                    for _, msg in ipairs(chat) do
                        imgui.Text(msg.sender..': '..msg.text);
                    end
                end
                imgui.EndChild();
                imgui.PushItemWidth(size.x - 10)
                if imgui.InputText('##sendChat', input.chat, ffi.sizeof(input.chat), imgui.InputTextFlags.EnterReturnsTrue) then
                    sendMessage(ffi.string(input.chat));
                    imgui.StrCopy(input.chat, '');
                end
                imgui.PopItemWidth();
            end
            imgui.End();
        end
    end
)

function imgui.CenterText(text)
    imgui.SetCursorPosX(imgui.GetWindowSize().x / 2 - imgui.CalcTextSize(text).x / 2)
    imgui.Text(text)
end