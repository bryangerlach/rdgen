## 使用 Docker 托管 RDGen 服务器

1. 首先，您需要在 GitHub 上 Fork 此仓库
2. 接下来，为您的 RDGen 仓库设置一个 GitHub 细粒度访问令牌，授予以下权限：
    * 登录您的 GitHub 账户
    * 点击右上角的个人头像，点击 Settings
    * 在左侧面板底部，点击 Developer Settings
    * 点击 Personal access tokens
    * 点击 Fine-grained tokens
    * 点击 Generate new token
    * 设置令牌名称，根据需要设置过期时间
    * 在 Repository access 下，选择 Only select repositories，然后选择您的 RDGen 仓库
    * 授予 actions 和 workflows 的读取和写入权限
    * 您可能需要前往 https://github.com/USERNAME/rdgen/actions 并点击绿色的 Enable Actions 按钮才能使其正常工作。
3. 登录您的 GitHub 账户，前往您的 RDGen 仓库页面 (https://github.com/USERNAME/rdgen)
    * 点击 Settings
    * 在左侧面板中点击 Secrets and variables，然后点击 Actions
    * 点击 New repository secret
    * 将 Name 设置为 GENURL
    * 将 Secret 设置为 https://rdgen.hostname.com（或您的服务器将被访问的地址）
    * 再次点击 New repository secret
    * 将 Name 设置为 ZIP_PASSWORD
    * 将 Secret 设置为您想用的任意密码（下一步也需要使用）—— 运行以下命令生成密码：```python3 -c 'import secrets; print(secrets.token_hex(100))'```
4. 下载 docker-compose.yml 文件并填写环境变量：
   * SECRET_KEY="您的密钥" —— 运行以下命令生成密钥：```python3 -c 'import secrets; print(secrets.token_hex(100))'```
   * GHUSER="您的 GitHub 用户名"
   * GHBEARER="您的细粒度访问令牌"
   * ZIP_PASSWORD="与您在 GitHub secret 中输入的相同密码"
   * PROTOCOL="https" *可选 —— 默认为 "https"，如需使用 HTTP 则改为 "http"
   * REPONAME="rdgen" *可选 —— 默认为 "rdgen"，如果您 Fork 时重命名了仓库，请修改此项
5. 运行 ```docker compose up -d```


## 使用自托管 GitHub Runner 加速客户端生成（目前仅支持 Windows）

1. 首先需要配置一台能够编译 RustDesk 的 Windows 计算机
2. 确认可以编译 RustDesk 后，按照 GitHub 官方指南设置自托管 Runner
3. 添加环境变量 SH_SECRET，其值为需要发送到服务器的密钥/密码
4. 从 RDGen 网页界面保存 JSON 配置文件
5. 使用 [rdgen-cli](https://github.com/AlekseyLapunov/rdgen-cli) 提交 JSON 配置，并添加 "sh_secret_field" 键，其值与您的 SH_SECRET 匹配

## 使用自己的 Windows 代码签名令牌

1. 需要将 USB 签名令牌插入 Windows 计算机
2. 在连接 USB 签名令牌的计算机上，确保已正确配置 signtool.exe 进行签名
3. 在连接 USB 令牌的计算机上运行一个小型[签名 API](https://github.com/bryangerlach/signing_api) 服务器。按照该服务器的安装说明进行设置。
4. 在您的 RDGen 仓库中添加以下 GitHub secrets：
   - SIGN_BASE_URL（签名 API 服务器在互联网上可访问的 URL）
   - SIGN_API_KEY（您在签名 API 服务器上设置的 API 密钥）


## 手动部署：

1. 拥有此仓库 Fork 的 GitHub 账户
2. 为您的 RDGen 仓库设置一个 GitHub 细粒度访问令牌，授予以下权限：
    * 登录您的 GitHub 账户
    * 点击右上角的个人头像，点击 Settings
    * 在左侧面板底部，点击 Developer Settings
    * 点击 Personal access tokens
    * 点击 Fine-grained tokens
    * 点击 Generate new token
    * 设置令牌名称，根据需要设置过期时间
    * 在 Repository access 下，选择 Only select repositories，然后选择您的 RDGen 仓库
    * 授予 actions 和 workflows 的读取和写入权限
    * 您可能需要前往 https://github.com/USERNAME/rdgen/actions 并点击绿色的 Enable Actions 按钮才能使其正常工作。
3. 配置环境变量/secrets：
    * 运行 RDGen 的服务器上的环境变量：
        * GHUSER="您的 GitHub 用户名"
        * GHBEARER="您的细粒度访问令牌"
        * PROTOCOL="https" *可选 —— 默认为 "https"，如需使用 HTTP 则改为 "http"
        * REPONAME="rdgen" *可选 —— 默认为 "rdgen"，如果您 Fork 时重命名了仓库，请修改此项
    * GitHub secrets（在您的 GitHub 账户中为 RDGen 仓库设置）：
        * GENURL="example.com:8000"  *这是您运行 RDGen 的域名和端口，需要在互联网上可访问，根据您的配置情况，可能不需要端口号

```
# 进入您要安装 RDGen 的目录（将 /opt 改为您想要的路径）
cd /opt

# 克隆您的 RDGen 仓库，将 bryangerlach 改为您的 GitHub 用户名
git clone https://github.com/bryangerlach/rdgen.git

# 进入 RDGen 目录
cd rdgen

# 创建 Python 虚拟环境，命名为 rdgen
python -m venv .venv

# 激活 Python 虚拟环境
source .venv/bin/activate

# 安装 Python 依赖
pip install -r requirements.txt

# 初始化数据库
python manage.py migrate

# 启动服务器，将 8000 改为您想要的端口
python manage.py runserver 0.0.0.0:8000
```

在浏览器中打开 yourdomain:8000

使用 nginx、caddy、traefik 等工具配置 SSL 反向代理

### 设置开机自启动，可以创建名为 rdgen.service 的 systemd 服务

根据需要替换 user、group 和 port，将 /opt 替换为您安装 RDGen 的路径。将以下文件保存为 /etc/systemd/system/rdgen.service，并确保修改 GHUSER 和 GHBEARER：

```
[Unit]
Description=RustDesk 客户端生成器
[Service]
Type=simple
LimitNOFILE=1000000
Environment="GHUSER=您的github用户名"
Environment="GHBEARER=您的github令牌"
PassEnvironment=GHUSER GHBEARER
ExecStart=/opt/rdgen/.venv/bin/python3 /opt/rdgen/manage.py runserver 0.0.0.0:8000
WorkingDirectory=/opt/rdgen/
User=root
Group=root
Restart=always
StandardOutput=file:/var/log/rdgen.log
StandardError=file:/var/log/rdgen.error
# 如果服务崩溃，10 秒后自动重启
RestartSec=10
[Install]
WantedBy=multi-user.target
```

然后运行以下命令启用开机自启动，并手动启动服务：

```
sudo systemctl enable rdgen.service
sudo systemctl start rdgen.service
```

查看服务器状态，运行：
```
sudo systemctl status rdgen.service
```
