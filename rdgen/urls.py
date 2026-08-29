"""
URL configuration for rdgen project.

The `urlpatterns` list routes URLs to views. For more information please see:
    https://docs.djangoproject.com/en/5.0/topics/http/urls/
Examples:
Function views
    1. Add an import:  from my_app import views
    2. Add a URL to urlpatterns:  path('', views.home, name='home')
Class-based views
    1. Add an import:  from other_app.views import Home
    2. Add a URL to urlpatterns:  path('', Home.as_view(), name='home')
Including another URLconf
    1. Import the include() function: from django.urls import include, path
    2. Add a URL to urlpatterns:  path('blog/', include('blog.urls'))
"""
import django

from rdgenerator import views as views
from rdgenerator import api_views as api_views
from rdgenerator import config_views as config_views
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
    # Saved-config console (order matters: specific routes before the list prefix)
    url(r'^configs/new$', config_views.config_new),
    url(r'^configs/save$', config_views.config_save),
    url(r'^configs/(?P<cfg>[0-9a-f-]{36})/edit$', config_views.config_edit),
    url(r'^configs/(?P<cfg>[0-9a-f-]{36})/duplicate$', config_views.config_duplicate),
    url(r'^configs/(?P<cfg>[0-9a-f-]{36})/delete$', config_views.config_delete),
    url(r'^configs/?$', config_views.configs_list),
    # JSON API endpoints
    url(r'^api/generate$',api_views.api_generate),
    url(r'^api/status$',api_views.api_status),
]
