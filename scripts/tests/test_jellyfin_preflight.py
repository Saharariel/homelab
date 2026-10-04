import importlib.util
import pathlib
import unittest
from unittest.mock import patch

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / 'jellyfin-preflight.py'


def load():
    assert SCRIPT.exists(), 'read-only preflight is not implemented'
    spec = importlib.util.spec_from_file_location('preflight', SCRIPT)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class PreflightTests(unittest.TestCase):
    def test_authenticated_inventory_redacts_users_and_plugin_configuration(self):
        module = load()
        responses = {
            '/System/Info/Public': {'Version': '10.11.11'},
            '/Plugins': [{'Name': 'LDAP-Auth', 'Version': '20.0', 'Status': 'Active',
                          'Configuration': 'SECRET'}],
            '/Users': [{'Name': 'SECRET', 'Id': 'SECRET', 'Policy': {
                'IsAdministrator': True, 'IsDisabled': False,
                'AuthenticationProviderId': 'Jellyfin.Plugin.LDAP_Auth.LdapAuthenticationProviderPlugin',
                'PasswordResetProviderId': 'SECRET'}}],
        }
        result = module.application_report(responses.__getitem__, authenticated=True)
        self.assertEqual(result['plugins'][0]['status'], 'Active')
        self.assertEqual(result['admin_auth']['enabled_admins'], 1)
        self.assertEqual(result['admin_auth']['ldap_only'], True)
        self.assertNotIn('SECRET', str(result))

    def test_cluster_inventory_only_gets_named_nonsecret_resources(self):
        module = load()
        commands = []
        template = {'spec': {'containers': [{'name': 'jellyfin',
                    'image': 'ghcr.io/jellyfin/jellyfin:10.11.11',
                    'env': [{'value': 'SECRET'}],
                    'resources': {'limits': {'gpu.intel.com/i915': '1'}},
                    'volumeMounts': [{'name': 'config', 'mountPath': '/config'},
                                     {'name': 'media', 'mountPath': '/data/media', 'readOnly': True}]}],
                    'volumes': [{'name': 'config', 'hostPath': {'path': '/var/lib/jellyfin-config'}},
                                {'name': 'media', 'persistentVolumeClaim': {'claimName': 'media-data'}}]}}
        responses = {
            ('deployment', 'jellyfin'): {'spec': {'replicas': 1, 'template': template}},
            ('pods', '-l', 'app=jellyfin'): {'items': [{'spec': {'nodeName': 'worker-node-1'},
                'status': {'phase': 'Running', 'containerStatuses': [{'name': 'jellyfin', 'ready': True,
                          'image': 'ghcr.io/jellyfin/jellyfin:10.11.11'}]}}]},
            ('node', 'worker-node-1'): {'status': {'allocatable': {'gpu.intel.com/i915': '1'},
                'conditions': [{'type': 'Ready', 'status': 'True'}]}},
            ('pvc', 'media-data'): {'spec': {'volumeName': 'media-pv'}, 'status': {'phase': 'Bound'}},
            ('pv', 'media-pv'): {'spec': {'nfs': {'server': 'nas', 'path': '/media'},
                'persistentVolumeReclaimPolicy': 'Retain', 'accessModes': ['ReadWriteMany']}},
        }

        def run(cmd, **kwargs):
            commands.append(cmd)
            key = tuple(cmd[cmd.index('get') + 1:cmd.index('-o')])
            import subprocess, json
            return subprocess.CompletedProcess(cmd, 0, json.dumps(responses[key]), '')

        with patch.object(module.subprocess, 'run', side_effect=run):
            result = module.cluster_report('media')
        self.assertEqual(result['config_host_path'], '/var/lib/jellyfin-config')
        self.assertEqual(result['nodes'][0]['name'], 'worker-node-1')
        self.assertTrue(result['media_mounts'][0]['read_only'])
        self.assertEqual(result['persistent_volumes'][0]['pv'], 'media-pv')
        self.assertNotIn('SECRET', str(result))
        self.assertTrue(all('get' in c and 'secrets' not in c for c in commands))

    def test_disk_refuses_wrong_node_before_touching_config(self):
        module = load()
        with patch.object(module.socket, 'gethostname', return_value='other'), \
                patch.object(module.os, 'statvfs') as stat:
            self.assertEqual(module.disk_report('/var/lib/jellyfin-config', 'worker-node-1'),
                             {'status': 'blocked: run locally on config node'})
            stat.assert_not_called()

    def test_disk_reports_available_bytes_without_reading_database(self):
        module = load()
        import types
        with patch.object(module.socket, 'gethostname', return_value='worker-node-1'), \
                patch.object(module.os, 'statvfs', return_value=types.SimpleNamespace(
                    f_bavail=100, f_frsize=4096, f_blocks=200, f_favail=50)):
            result = module.disk_report('/var/lib/jellyfin-config', 'worker-node-1')
        self.assertEqual(result['available_bytes'], 409600)
        self.assertEqual(result['available_inodes'], 50)

    def test_cli_dry_run_blocks_backup_and_sanitizes_errors(self):
        module = load()
        import contextlib, io
        output = io.StringIO()
        with patch.object(module, 'cluster_report', side_effect=RuntimeError('SECRET')), \
                patch.object(module, 'make_api', return_value=lambda path: {'Version': '10.11.11'}), \
                contextlib.redirect_stdout(output):
            code = module.main([])
        import json
        result = json.loads(output.getvalue())
        self.assertEqual(code, 2)
        self.assertTrue(result['dry_run'])
        self.assertEqual(result['backup_execution'], 'unsupported')
        self.assertIn('cold-backup authorization not provided', result['blocked_gates'])
        self.assertNotIn('SECRET', output.getvalue())

    def test_backup_gates_do_not_accept_zero_replicas_with_live_pods(self):
        module = load()
        cluster = {'desired_replicas': 0, 'pods': [{'phase': 'Running'}]}
        self.assertIn('Jellyfin not proven stopped', module.cold_backup_gates(cluster, True))
        self.assertNotIn('Jellyfin not proven stopped',
                         module.cold_backup_gates({'desired_replicas': 0, 'pods': []}, True))

    def test_incomplete_admin_inventory_never_claims_ldap_only(self):
        module = load()
        responses = {'/System/Info/Public': {'Version': '10.11.11'}, '/Plugins': [],
                     '/Users': [{'Policy': {'IsAdministrator': True, 'IsDisabled': False,
                         'AuthenticationProviderId': 'Jellyfin.Plugin.LDAP_Auth.LdapAuthenticationProviderPlugin'}},
                         {'Policy': {'IsAdministrator': True}}]}
        result = module.application_report(responses.__getitem__, True)
        self.assertFalse(result['admin_auth']['ldap_only'])

    def test_plugin_permission_error_preserves_public_version_without_error_text(self):
        module = load()
        def api(path):
            if path == '/System/Info/Public':
                return {'Version': '10.11.11'}
            raise RuntimeError('SECRET')
        result = module.application_report(api, True)
        self.assertEqual(result['version'], '10.11.11')
        self.assertIn('blocked', result['plugins'])
        self.assertNotIn('SECRET', str(result))

    def test_missing_admin_policy_fails_closed(self):
        module = load()
        responses = {'/System/Info/Public': {'Version': '10.11.11'}, '/Plugins': [],
                     '/Users': [{'Policy': {'IsAdministrator': True}}]}
        result = module.application_report(responses.__getitem__, True)
        self.assertFalse(result['admin_auth']['ldap_only'])

    def test_api_disallows_remote_plaintext_and_url_credentials(self):
        module = load()
        for url in ['http://example.com', 'https://user:SECRET@example.com',
                    'https://example.com?api_key=SECRET', 'file:///tmp/config']:
            with self.assertRaises(ValueError):
                module.make_api(url, 'TOKEN')

    def test_api_get_only_does_not_follow_redirects(self):
        module = load()
        import urllib.error
        api = module.make_api('http://127.0.0.1:30096', 'TOKEN')
        from email.message import Message
        with patch.object(module.urllib.request.OpenerDirector, 'open',
                          side_effect=urllib.error.HTTPError('url', 302, 'SECRET', Message(), None)) as opened:
            with self.assertRaises(urllib.error.HTTPError):
                api('/Plugins')
            request = opened.call_args.args[0]
            self.assertEqual(request.get_method(), 'GET')
            self.assertNotIn('TOKEN', request.full_url)
        with self.assertRaises(ValueError):
            api('/Users/SECRET')
        with self.assertRaises(urllib.error.HTTPError):
            module.NoRedirect().redirect_request(None, None, 302, 'SECRET', {}, 'https://other')

    def test_public_version_no_credentials(self):
        module = load()
        calls = []

        def api(path):
            calls.append(path)
            return {'Version': '10.11.11', 'AccessToken': 'DO-NOT-OUTPUT'}

        result = module.application_report(api, authenticated=False)
        self.assertEqual(result['version'], '10.11.11')
        self.assertEqual(calls, ['/System/Info/Public'])
        self.assertEqual(result['plugins'], 'blocked: credentials not supplied')
        self.assertNotIn('DO-NOT-OUTPUT', str(result))


if __name__ == '__main__':
    unittest.main()
