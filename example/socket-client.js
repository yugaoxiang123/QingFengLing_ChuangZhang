// DOM元素
const serverIPInput = document.getElementById('serverIP');
const serverPortInput = document.getElementById('serverPort');
const connectBtn = document.getElementById('connectBtn');
const disconnectBtn = document.getElementById('disconnectBtn');
const statusText = document.getElementById('status');
const messageInput = document.getElementById('message');
const sendBtn = document.getElementById('sendBtn');
const messageLog = document.getElementById('messageLog');

// WebSocket连接
let socket = null;
let reconnectAttempts = 0;
let reconnectTimeout = null;
const MAX_RECONNECT_ATTEMPTS = 5;

// 添加消息到日志
function logMessage(message, type) {
    const messageElement = document.createElement('div');
    messageElement.classList.add(type);
    messageElement.textContent = `[${new Date().toLocaleTimeString()}] ${message}`;
    messageLog.appendChild(messageElement);
    messageLog.scrollTop = messageLog.scrollHeight;
}

// 更新UI状态
function updateUIState(connected) {
    connectBtn.disabled = connected;
    disconnectBtn.disabled = !connected;
    sendBtn.disabled = !connected;
    
    statusText.textContent = connected ? '已连接' : '未连接';
    statusText.style.color = connected ? '#4CAF50' : '#cc0000';
}

// 连接服务器
function connectToServer() {
    const ip = serverIPInput.value.trim();
    const port = serverPortInput.value.trim();
    
    if (!ip || !port) {
        logMessage('请输入有效的服务器IP和端口', 'error');
        return;
    }
    
    try {
        // 使用正确的WebSocket路径
        socket = new WebSocket(`ws://${ip}:${port}/ws`);
        
        logMessage(`尝试连接到 ws://${ip}:${port}/ws`, 'system');
        
        socket.onopen = () => {
            updateUIState(true);
            logMessage(`成功连接到服务器 ${ip}:${port}`, 'system');
            // 成功连接后重置重连计数器
            reconnectAttempts = 0;
            if (reconnectTimeout) {
                clearTimeout(reconnectTimeout);
                reconnectTimeout = null;
            }
        };
        
        socket.onmessage = (event) => {
            const message = event.data;
            logMessage(`收到消息: ${message}`, 'received');
        };
        
        socket.onclose = (event) => {
            logMessage(`与服务器的连接已关闭${event.wasClean ? '（正常关闭）' : '（异常关闭）'}`, 'system');
            updateUIState(false);
            
            // 如果不是用户主动关闭，尝试重连
            if (!event.wasClean && reconnectAttempts < MAX_RECONNECT_ATTEMPTS) {
                reconnectAttempts++;
                const delay = Math.min(1000 * Math.pow(2, reconnectAttempts - 1), 30000);
                logMessage(`将在 ${delay/1000} 秒后尝试重新连接... (${reconnectAttempts}/${MAX_RECONNECT_ATTEMPTS})`, 'system');
                
                reconnectTimeout = setTimeout(() => {
                    if (connectBtn.disabled === false) { // 如果用户没有手动连接
                        connectToServer();
                    }
                }, delay);
            } else if (reconnectAttempts >= MAX_RECONNECT_ATTEMPTS) {
                logMessage('达到最大重连次数，请手动重新连接', 'error');
                reconnectAttempts = 0;
            }
            
            socket = null;
        };
        
        socket.onerror = (error) => {
            logMessage(`连接错误: ${error.message || '未知错误'}`, 'error');
        };
    } catch (error) {
        logMessage(`连接失败: ${error.message}`, 'error');
        updateUIState(false);
    }
}

// 连接按钮事件处理
connectBtn.addEventListener('click', () => {
    connectToServer();
});

// 断开连接
disconnectBtn.addEventListener('click', () => {
    if (socket) {
        // 停止任何正在进行的重连尝试
        if (reconnectTimeout) {
            clearTimeout(reconnectTimeout);
            reconnectTimeout = null;
        }
        reconnectAttempts = 0;
        
        // 正常关闭连接
        socket.close(1000, "用户主动断开连接");
        logMessage('已断开连接', 'system');
        updateUIState(false);
    }
});

// 发送消息
sendBtn.addEventListener('click', () => {
    if (!socket) {
        logMessage('未连接到服务器', 'error');
        return;
    }
    
    const message = messageInput.value.trim();
    if (!message) {
        logMessage('请输入要发送的消息', 'error');
        return;
    }
    
    try {
        socket.send(message);
        logMessage(`已发送: ${message}`, 'sent');
        messageInput.value = '';
    } catch (error) {
        logMessage(`发送失败: ${error.message}`, 'error');
    }
});

// 键盘事件监听
messageInput.addEventListener('keypress', (event) => {
    if (event.key === 'Enter' && !sendBtn.disabled) {
        sendBtn.click();
    }
});

// 添加自动重连的选项
const autoReconnectCheckbox = document.createElement('input');
autoReconnectCheckbox.type = 'checkbox';
autoReconnectCheckbox.id = 'autoReconnect';
autoReconnectCheckbox.checked = true;

const autoReconnectLabel = document.createElement('label');
autoReconnectLabel.htmlFor = 'autoReconnect';
autoReconnectLabel.textContent = '自动重连';

const controlsContainer = document.querySelector('.controls');
const autoReconnectContainer = document.createElement('div');
autoReconnectContainer.className = 'control-group';
autoReconnectContainer.appendChild(autoReconnectCheckbox);
autoReconnectContainer.appendChild(autoReconnectLabel);
controlsContainer.appendChild(autoReconnectContainer);

// 初始化
updateUIState(false);
logMessage('WebSocket测试客户端已准备就绪', 'system');
logMessage('请输入服务器IP和端口，然后点击"连接服务器"', 'system'); 
logMessage('注意: 请确保使用WebSocket端口(默认8889)而不是原始Socket端口', 'system'); 