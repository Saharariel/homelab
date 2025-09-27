# 🏠 Homelab Infrastructure

This repository contains the GitOps-managed configuration for all the self-hosted services on my homelab Kubernetes cluster using K3s

## Overview

This repository follows a GitOps approach to manage and automate the infrastructure and services running in my homelab. All Kubernetes manifests and Helm releases are stored and version-controlled here, making it easy to replicate, recover, and scale the setup.

Originally, I ran everything with Docker and Docker Compose. But as my setup grew in complexity, I decided to migrate to Kubernetes.

Admittedly, this is overkill for a homelab - but that's kind of the point. This project is my playground for learning Kubernetes through hands-on experience, while also powering the self-hosted services I use every day.

## Infrastructure Specs

### Control Plane 
**Dell Vostro Laptop** 
- **CPU:** Intel Core i5-8265U 
- **Memory:** 8 GB DDR4 RAM 
- **Storage:** 256GB SSD
- **OS:** Ubuntu Server

### Worker Node
- **CPU:** Intel Core i7-8700  
- **Memory:** 16 GB DDR4 RAM
- **Storage:** 12 TB HDD  
- **Hypervisor:** Proxmox VE
- **OS:** Ubuntu Server (running in VM)

## Core Apps & Tools

### Apps

Services i use everyday
<table>
    <tr>
        <th>Logo</th>
        <th>Name</th>
        <th>Description</th>
    </tr>
    <tr>
    <td>
        <img width="34" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/jellyfin.svg" style="padding-top:6px;">
        </td>
        <td>
        <a href="https://jellyfin.org/">Jellyfin</a>
    </td>
    <td>The Open-Source Media System</td>
    </tr>
    <tr>
    <td>
        <img width="34" src="https://raw.githubusercontent.com/homarr-labs/dashboard-icons/a2594d147cfd8eabca0ea40474e532377aebbb44/svg/jellyseerr.svg" style="padding-top:6px;">
        </td>
        <td>
        <a href="https://docs.jellyseerr.dev/">Jellyseer</a>
    </td>
    <td>Requests manager for media library</td>
    </tr>
    <tr>
    <td>
        <img width="34" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/n8n.svg" style="padding-top:6px;">
        </td>
        <td>
        <a href="https://n8n.io/">n8n</a>
    </td>
    <td>Secure, AI-native workflow automation</td>
    </tr>
    <tr>
    <td>
        <img width="34" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/homarr.svg" style="padding-top:6px;">
        </td>
        <td>
        <a href="https://homarr.dev/">Homarr</a>
    </td>
    <td>A sleek, modern dashboard</td>
    </tr>
    <tr>
    <td>
        <img width="34" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/authentik.svg" style="padding-top:6px;">
        </td>
        <td>
        <a href="https://goauthentik.io/">Authentik</a>
    </td>
    <td>Identity provider</td>
    </tr>
</table> 

### Infrastructure

Everything needed to run my cluster & deploy my applications
<table>
    <tr>
        <th>Logo</th>
        <th>Name</th>
        <th>Description</th>
    </tr>
    <tr>
    <td>
        <img width="34" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/flux-cd.svg" style="padding-top:6px;">
        </td>
        <td>
        <a href="https://fluxcd.io/">Flux-CD</a>
    </td>
    <td>My GitOps solution of choice</td>
    </tr>
    <tr>
    <td>
        <img width="34" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/renovate.svg" style="padding-top:6px;">
        </td>
        <td>
        <a href="https://docs.renovatebot.com/">Renovate</a>
    </td>
    <td>Automated dependency updates.</td>
    </tr>
    <tr>
    <td>
        <img width="34" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/prometheus.svg" style="padding-top:6px;">
        </td>
        <td>
        <a href="https://prometheus.io/">Prometheus</a>
    </td>
    <td>Metrics and monitoring for your systems and services</td>
    </tr>
    <tr>
    <td>
        <img width="34" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/grafana.svg" style="padding-top:6px;">
        </td>
        <td>
        <a href="https://grafana.com/">Grafana</a>
    </td>
    <td>Platform for visualizing metrics</td>
    </tr>
    <tr>
    <td>
        <img width="34" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/cloudflare.svg" style="padding-top:6px;">
        </td>
        <td>
        <a href="https://developers.cloudflare.com/cloudflare-one">Cloudflare Zero Trust</a>
    </td>
    <td>Used for private tunnels to expose public services</td>
    </tr>
    <tr>
    <td>
        <img width="34" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/proxmox.svg" style="padding-top:6px;">
        </td>
        <td>
        <a href="https://www.proxmox.com/en/">Proxmox</a>
    </td>
    <td>Open-source Hypervisor</td>
    </tr>
    <tr>
    <td>
        <img width="34" src="https://avatars.githubusercontent.com/u/129185620?s=200&v=4" style="padding-top:6px;">
        </td>
        <td>
        <a href="https://github.com/getsops/sops">SOPS</a>
    </td>
    <td>Simple And Flexible Tool For Managing Secrets</td>
    </tr>
</table> 


## My Goals in this Project

- Automate and version all infrastructure and services  
- Ensure reproducibility and recoverability  
- Improve DevOps skills using real-world tools and patterns  
- Provide secure, performant, and resilient home services 