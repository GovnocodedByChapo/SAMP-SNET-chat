import { SNetServer, BitStream, SNET_PRIORITES } from './snet';
const server = new SNetServer({ port: 11321 });
server.on('ready', () => {
    console.log('@server: started');
});

enum Packet {
    Ping,
    Pong,
    Registration,
    RegistrationResponse,
    Login,
    LoginResponse,
    SendMessage,
    NewMessage,
    UserJoin,
    UserQuit
};

interface User {
    login: string,
    password: string,
    avatarUrl?: string
};

interface Message {
    author: string,
    text: string,
    timestamp: number
}

const users: Record<string, User> = {};
const chat: Message[] = [];

server.on('onReceivePacket', async (id, bs, ip, port) => {
    if (id == Packet.Ping) {
        const bs = new BitStream();
        bs.writeInt8(4);
        bs.writeString('Pong');
        server.send(Packet.Pong, bs, SNET_PRIORITES.SYSTEM, ip, port);
    } else if (id == Packet.Registration) {
        const login = bs.readString(bs.readInt16());
        const password = bs.readString(bs.readInt16());
        const status = users[login] == undefined && password.length > 3

        if (status) {
            const joinNotification = new BitStream();
            joinNotification.writeInt16(login.length);
            joinNotification.writeString(login);
            server.sendAll(Packet.UserJoin, joinNotification, SNET_PRIORITES.HIGH);
            users[login] = {
                login: login,
                password: password,
            };

            // send all chat history
            for (const message of chat) {
                const msg = new BitStream();
                msg.writeInt32(message.text.length);
                msg.writeString(message.text);
                msg.writeInt16(message.author.length);
                msg.writeString(message.author);
                msg.writeInt32(message.timestamp);
                msg.writeBoolean(true);
                server.send(Packet.NewMessage, msg, SNET_PRIORITES.HIGH, ip, port);
            };
        };

        const response = new BitStream();
        response.writeBoolean(status);
        response.writeInt16(login.length);
        response.writeString(login);
        console.log(login)
        return server.send(Packet.RegistrationResponse, response, SNET_PRIORITES.SYSTEM, ip, port);
    } else if (id == Packet.Login) {
        const login = bs.readString(bs.readInt16());
        const password = bs.readString(bs.readInt16());
        const status = users?.[login]?.password == password;
        console.log(`[AUTH] Login: ${login} Password: ${password} Status: ${status}`);
        if (status) {
            const joinNotification = new BitStream();
            joinNotification.writeInt16(login.length);
            joinNotification.writeString(login);
            server.sendAll(Packet.UserJoin, joinNotification, SNET_PRIORITES.HIGH);
        };
        
        const response = new BitStream();
        response.writeBoolean(status);
        response.writeInt16(login.length);
        response.writeString(login);
        response.writeInt16(password.length);
        response.writeString(password);
        return server.send(Packet.LoginResponse, response, SNET_PRIORITES.SYSTEM, ip, port);
    } else if (id == Packet.SendMessage) {
        const text = bs.readString(bs.readUInt32());
        const sender = bs.readString(bs.readUInt16());
        const timestamp = bs.readInt32();
        console.log(`[${timestamp}] ${sender}: ${text}`);
        chat.push({
            text: text,
            author: sender,
            timestamp: timestamp
        });
        return server.sendAll(Packet.NewMessage, bs, SNET_PRIORITES.HIGH);
    } else if (id == Packet.UserQuit) {
        return server.sendAll(Packet.UserQuit, bs, SNET_PRIORITES.HIGH);
    };
});

