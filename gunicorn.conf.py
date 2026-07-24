import os

# 根据需要调整以下参数
bind = "0.0.0.0:8000"  # Gunicorn 监听的主机和端口
workers = 5  # 并发工作进程数（根据系统资源调整）
threads = 6
activate_base = True  # 如适用，激活虚拟环境

# Django 项目主 WSGI 应用文件路径
wsgi_app = "rdgen.wsgi.application"
