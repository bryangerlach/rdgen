from django.db import models

class GithubRun(models.Model):
    id = models.IntegerField(verbose_name="ID",primary_key=True)
    uuid = models.CharField(verbose_name="UUID", max_length=100)
    status = models.CharField(verbose_name="状态", max_length=100)
    github_run_id = models.BigIntegerField(null=True, blank=True)
    run_ids = models.TextField(null=True, blank=True, verbose_name="全部工作流运行ID")
