"""
rdgen 项目的 WSGI 配置

它将 WSGI 可调用对象作为名为 ``application`` 的模块级变量暴露出来。

更多信息请参阅：
https://docs.djangoproject.com/en/5.0/howto/deployment/wsgi/
"""

import os

from django.core.wsgi import get_wsgi_application

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'rdgen.settings')

application = get_wsgi_application()
