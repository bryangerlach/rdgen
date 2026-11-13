import json
import os
import tempfile
from unittest import mock

from django.test import RequestFactory, SimpleTestCase, TestCase, override_settings

from .views import get_full_url


class GetFullUrlTests(SimpleTestCase):
    def setUp(self):
        self.request = RequestFactory().get('/', HTTP_HOST='127.0.0.1:8000')

    @override_settings(GENURL='', PROTOCOL='https')
    def test_uses_request_host_without_genurl(self):
        self.assertEqual(get_full_url(self.request), 'https://127.0.0.1:8000')

    @override_settings(GENURL='https://rdgen.example.com:4433/', PROTOCOL='https')
    def test_uses_genurl(self):
        self.assertEqual(get_full_url(self.request), 'https://rdgen.example.com:4433')

    @override_settings(GENURL='rdgen.example.com:8000', PROTOCOL='http')
    def test_adds_protocol_to_genurl_without_one(self):
        self.assertEqual(get_full_url(self.request), 'http://rdgen.example.com:8000')


@override_settings(GENURL='https://rdgen.example.com', PROTOCOL='https')
class GeneratorViewTests(TestCase):
    def setUp(self):
        cwd = os.getcwd()
        tmp = tempfile.TemporaryDirectory()
        os.chdir(tmp.name)
        self.addCleanup(tmp.cleanup)
        self.addCleanup(os.chdir, cwd)

    def test_workflow_downloads_zip_from_genurl(self):
        github = mock.Mock(status_code=200)
        github.json.return_value = {'workflow_run_id': 1, 'html_url': ''}
        with mock.patch('rdgenerator.views.requests.post', return_value=github) as post:
            self.client.post('/generator', {
                'platform': 'windows',
                'version': '1.5.3',
                'exename': 'client',
                'direction': 'both',
                'installation': 'installationY',
                'settings': 'settingsY',
                'theme': 'system',
                'themeDorO': 'default',
                'passApproveMode': 'password-click',
                'permissionsType': 'custom',
            }, HTTP_HOST='127.0.0.1')

        post.assert_called_once()
        zip_url = json.loads(post.call_args.kwargs['json']['inputs']['zip_url'])
        self.assertEqual(zip_url['url'], 'https://rdgen.example.com')
