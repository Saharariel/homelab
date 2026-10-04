#!/usr/bin/env python3
"""Read-only Jellyfin inventory. No backup, migration, or mutation capability."""


import argparse
import json
import sys
import urllib.error
import urllib.parse
import urllib.request
import os
import socket
import subprocess


def kube_get(namespace, *resource):
    scope = ['-n', namespace] if namespace else []
    result = subprocess.run(
        ['kubectl', '--request-timeout=10s', *scope, 'get', *resource, '-o', 'json'],
        capture_output=True, text=True, check=True, timeout=20)
    return json.loads(result.stdout)


def cluster_report(namespace):
    deployment = kube_get(namespace, 'deployment', 'jellyfin')
    spec = deployment['spec']['template']['spec']
    container = next(c for c in spec['containers'] if c['name'] == 'jellyfin')
    pods = kube_get(namespace, 'pods', '-l', 'app=jellyfin')['items']
    nodes = []
    for name in sorted({p['spec']['nodeName'] for p in pods if p['spec'].get('nodeName')}):
        node = kube_get(None, 'node', name)
        nodes.append({'name': name,
                      'ready': any(c['type'] == 'Ready' and c['status'] == 'True'
                                   for c in node['status']['conditions']),
                      'intel_gpu_allocatable': node['status']['allocatable'].get('gpu.intel.com/i915')})
    volumes = spec['volumes']
    persistent_volumes = []
    for volume in volumes:
        if 'persistentVolumeClaim' not in volume:
            continue
        claim = volume['persistentVolumeClaim']['claimName']
        pvc = kube_get(namespace, 'pvc', claim)
        pv_name = pvc['spec'].get('volumeName')
        pv = kube_get(None, 'pv', pv_name)['spec'] if pv_name else {}
        persistent_volumes.append({
            'claim': claim, 'phase': pvc['status']['phase'], 'pv': pv_name,
            'backend': next((k for k in ('nfs', 'csi', 'hostPath', 'local') if k in pv), 'unknown'),
            'access_modes': pv.get('accessModes'),
            'reclaim_policy': pv.get('persistentVolumeReclaimPolicy'),
            'node_affinity': pv.get('nodeAffinity'),
        })
    config = next(v for v in volumes if v['name'] == 'config')
    return {
        'desired_image': container['image'],
        'desired_replicas': deployment['spec'].get('replicas', 1),
        'pods': [{'node': p['spec'].get('nodeName'), 'phase': p['status']['phase'],
                  'containers': [{'image': c['image'], 'ready': c['ready']}
                                 for c in p['status'].get('containerStatuses', [])
                                 if c['name'] == 'jellyfin']} for p in pods],
        'nodes': nodes,
        'node_selector': spec.get('nodeSelector', {}),
        'node_affinity': spec.get('affinity', {}).get('nodeAffinity'),
        'config_host_path': config.get('hostPath', {}).get('path'),
        'intel_gpu_limit': container.get('resources', {}).get('limits', {}).get('gpu.intel.com/i915'),
        'media_mounts': [{'path': m['mountPath'], 'read_only': m.get('readOnly', False)}
                         for m in container['volumeMounts'] if m['name'] == 'media'],
        'persistent_volumes': persistent_volumes,
    }


def disk_report(path, node):
    if socket.gethostname().split('.')[0] != node:
        return {'status': 'blocked: run locally on config node'}
    stat = os.statvfs(path)
    return {'status': 'observed', 'path': path,
            'available_bytes': stat.f_bavail * stat.f_frsize,
            'total_bytes': stat.f_blocks * stat.f_frsize,
            'available_inodes': stat.f_favail,
            'config_size': 'unmeasured: no recursive config/database reads'}


def application_report(api, authenticated=False):
    report = {'version': api('/System/Info/Public')['Version'],
              'plugins': 'blocked: credentials not supplied',
              'admin_auth': 'blocked: credentials not supplied'}
    if not authenticated:
        return report
    try:
        report['plugins'] = [
            {'name': p['Name'], 'version': p['Version'], 'status': p.get('Status', 'unknown')}
            for p in api('/Plugins')]
    except Exception:
        report['plugins'] = 'blocked: plugin inventory unavailable'
    try:
        users = api('/Users')
        complete = all(isinstance(u.get('Policy', {}).get('IsAdministrator'), bool)
                       and isinstance(u.get('Policy', {}).get('IsDisabled'), bool) for u in users)
        admins = [u['Policy'] for u in users
                  if u.get('Policy', {}).get('IsAdministrator') is True
                  and u.get('Policy', {}).get('IsDisabled') is False]
        providers = [p.get('AuthenticationProviderId', 'unknown') for p in admins]
        report['admin_auth'] = {
            'inventory_complete': complete,
            'enabled_admins': len(admins),
            'providers': sorted(set(providers)),
            'ldap_only': complete and bool(admins) and all(
                p == 'Jellyfin.Plugin.LDAP_Auth.LdapAuthenticationProviderPlugin'
                for p in providers),
            'login_verified': False,
        }
    except Exception:
        report['admin_auth'] = 'blocked: admin provider inventory unavailable'
    return report


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise urllib.error.HTTPError('redacted', code, 'redirect refused', headers, fp)


def make_api(base_url, token=''):
    parsed = urllib.parse.urlsplit(base_url)
    if (parsed.scheme not in ('http', 'https') or not parsed.hostname
            or parsed.username or parsed.password or parsed.query or parsed.fragment
            or (parsed.scheme == 'http' and parsed.hostname not in ('127.0.0.1', '::1', 'localhost'))):
        raise ValueError('unsafe endpoint')
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())

    def get(path):
        if path not in ('/System/Info/Public', '/Plugins', '/Users'):
            raise ValueError('endpoint not allowlisted')
        headers = {'Accept': 'application/json'}
        if token and path != '/System/Info/Public':
            headers['X-Emby-Token'] = token
        request = urllib.request.Request(base_url.rstrip('/') + path, headers=headers, method='GET')
        with opener.open(request, timeout=10) as response:
            return json.load(response)

    return get


def cold_backup_gates(cluster, authorized=False):
    gates = []
    if not authorized:
        gates.append('cold-backup authorization not provided')
    if cluster.get('desired_replicas') != 0 or cluster.get('pods') != []:
        gates.append('Jellyfin not proven stopped')
    gates.extend([
        'all config writers stopped and reconciliation held: not independently verified',
        'protected remote Proxmox destination, capacity and archive hashes: not verified',
        'isolated restore and rollback rehearsal: not performed',
    ])
    return gates


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--namespace', default='media')
    parser.add_argument('--url', default='http://127.0.0.1:30096')
    parser.add_argument('--token-stdin', action='store_true',
                        help='Use an existing operator-supplied token; never read Kubernetes Secrets')
    args = parser.parse_args(argv)
    report: dict = {'dry_run': True, 'backup_execution': 'unsupported'}
    try:
        report['cluster'] = cluster_report(args.namespace)
    except Exception:
        report['cluster'] = {'status': 'blocked: Kubernetes inventory unavailable'}
    try:
        token = sys.stdin.readline().strip() if args.token_stdin else ''
        if args.token_stdin and not token:
            raise ValueError('missing token')
        report['application'] = application_report(make_api(args.url, token), bool(token))
    except Exception:
        report['application'] = {'status': 'blocked: application inventory unavailable'}
    cluster = report['cluster']
    nodes = [n['name'] for n in cluster.get('nodes', [])]
    try:
        if nodes != ['worker-node-1'] or cluster.get('config_host_path') != '/var/lib/jellyfin-config':
            raise ValueError('unverified config location')
        report['disk'] = disk_report(cluster['config_host_path'], nodes[0])
    except Exception:
        report['disk'] = {'status': 'blocked: local config filesystem unavailable or location unverified'}
    report['blocked_gates'] = cold_backup_gates(cluster)
    report['blocked_gates'].append('target release and loaded plugins compatibility: not verified')
    if not isinstance(report.get('application', {}).get('admin_auth'), dict):
        report['blocked_gates'].append('admin authentication providers and loaded plugins: not verified')
    else:
        report['blocked_gates'].append('LDAP and independent recovery-admin login rehearsal: not performed')
    print(json.dumps(report, indent=2, sort_keys=True))
    return 2  # Inventory is not upgrade/backup authorization, even when GETs succeed.


if __name__ == '__main__':
    sys.exit(main())
