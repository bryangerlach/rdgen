"""
rdgen 项目的 URL 配置

`urlpatterns` 列表将 URL 路由到视图。更多信息请参阅：
    https://docs.djangoproject.com/en/5.0/topics/http/urls/
示例：
函数视图
    1. 添加导入：from my_app import views
    2. 添加 URL 到 urlpatterns：path('', views.home, name='home')
基于类的视图
    1. 添加导入：from other_app.views import Home
    2. 添加 URL 到 urlpatterns：path('', Home.as_view(), name='home')
包含其他 URLconf
    1. 导入 include() 函数：from django.urls import include, path
    2. 添加 URL 到 urlpatterns：path('blog/', include('blog.urls'))
"""
import django

from rdgenerator import views as views
if django.__version__.split('.')[0]>='4':
    from django.urls import re_path as url
else:
    from django.conf.urls import  url, include

urlpatterns = [
    url(r'^$',views.generator_view),
    url(r'^generator',views.generator_view),
    url(r'^check_for_file',views.check_for_file),
    url(r'^download',views.download),
    url(r'^creategh',views.create_github_run),
    url(r'^updategh',views.update_github_run),
    url(r'^startgh',views.startgh),
    url(r'^get_png',views.get_png),
    url(r'^save_custom_client',views.save_custom_client),
    url(r'^get_zip',views.get_zip),
    url(r'^cleanzip',views.cleanup_secrets),
]
